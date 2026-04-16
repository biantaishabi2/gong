defmodule Gong.PhiHybridOrchestrator do
  @moduledoc """
  Φ 混合策略编排器（#2846）。

  先用 Prompt 引导生成 1 个候选（1× 成本）→ Φ 打分 → 分数 > 阈值则用
  → 否则升级生成 K-1 个额外候选做 Best-of-K（K× 成本）。

  ## 设计决策

  ### 升级判定规则
  - 使用绝对阈值（`score_threshold`），按场景可配置
  - 首候选解析失败时直接升级（视为 score = -∞）
  - 升级时再生成 K-1 个候选（不重复首候选的 LLM 调用）

  ### 成本预算契约
  - 单步最大调用数固定为 K（含首候选的 1 次）
  - 通过 telemetry 记录每步实际调用数
  - 不升级时 cost = 1×，升级时 cost = K×

  ### 降级路径
  - Best-of-K 分支全部失败 → 回退首候选（即使分数低）
  - 并发调用部分失败 → 用剩余成功候选继续选择
  - guidance / scorer 异常 → 跳过，不阻断主循环

  ## 使用方式

      orchestrator = PhiHybridOrchestrator.new(
        phi_id: "phi_methodical",
        k: 5,
        score_threshold: 1.0
      )

      {:ok, response, orchestrator, telemetry} =
        PhiHybridOrchestrator.run_step(orchestrator, agent, call_id, llm_backend)
  """

  require Logger

  alias Gong.PhiCandidateSelector

  @type t :: %__MODULE__{
          phi_id: String.t() | nil,
          k: pos_integer(),
          score_threshold: float(),
          selector: PhiCandidateSelector.t(),
          total_steps: non_neg_integer(),
          upgraded_steps: non_neg_integer(),
          total_llm_calls: non_neg_integer()
        }

  defstruct phi_id: nil,
            k: 5,
            score_threshold: 1.0,
            selector: nil,
            total_steps: 0,
            upgraded_steps: 0,
            total_llm_calls: 0

  @type step_telemetry :: %{
          step: non_neg_integer(),
          upgraded: boolean(),
          llm_calls: pos_integer(),
          first_score: float() | nil,
          final_score: float() | nil,
          final_action: String.t() | nil,
          threshold: float(),
          all_scores: [float()],
          fallback_used: boolean()
        }

  @doc "创建新的混合编排器。"
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    phi_id = Keyword.get(opts, :phi_id)
    k = Keyword.get(opts, :k, 5)
    threshold = Keyword.get(opts, :score_threshold, 1.0)

    selector = PhiCandidateSelector.new(phi_id: phi_id, k: k)

    %__MODULE__{
      phi_id: phi_id,
      k: k,
      score_threshold: threshold,
      selector: selector
    }
  end

  @doc """
  执行一步混合策略。

  1. 注入 Φ guidance（如果 PhiGuidanceHook 已激活，guidance 已在 conversation 中）
  2. 生成 1 个候选 → 解析 + 打分
  3. 分数 >= threshold → 直接使用（1× 成本）
  4. 分数 < threshold → 升级生成 K-1 个额外候选 → Best-of-K 选择（K× 成本）

  返回 `{:ok, response, updated_orchestrator, step_telemetry}`
  或 `{:error, reason}`
  """
  @spec run_step(t(), struct(), String.t(), function()) ::
          {:ok, term(), t(), step_telemetry()} | {:error, term()}
  def run_step(%__MODULE__{} = orch, agent, call_id, llm_backend) do
    step_num = orch.total_steps + 1

    # 阶段 1：生成首候选（1× 成本）
    case generate_first_candidate(agent, call_id, llm_backend) do
      {:ok, first_response} ->
        # 解析 + 打分
        case score_response(first_response, orch.selector) do
          {:ok, first_score, first_action, first_candidate} ->
            if first_score >= orch.score_threshold do
              # 达标 → 不升级
              handle_accepted(orch, first_response, first_candidate, first_score, first_action, step_num)
            else
              # 不达标 → 升级 Best-of-K
              handle_upgrade(orch, agent, call_id, llm_backend, first_response, first_candidate, first_score, step_num)
            end

          :parse_failed ->
            # 解析失败 → 直接升级
            handle_upgrade(orch, agent, call_id, llm_backend, first_response, nil, nil, step_num)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  在 action 执行后更新 scorer 状态。
  """
  @spec update_after_execution(t(), String.t(), keyword()) :: t()
  def update_after_execution(%__MODULE__{} = orch, action, opts \\ []) do
    updated_selector = PhiCandidateSelector.update_after_execution(orch.selector, action, opts)
    %{orch | selector: updated_selector}
  end

  @doc """
  获取累计统计摘要。
  """
  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = orch) do
    %{
      total_steps: orch.total_steps,
      upgraded_steps: orch.upgraded_steps,
      total_llm_calls: orch.total_llm_calls,
      upgrade_rate: if(orch.total_steps > 0, do: orch.upgraded_steps / orch.total_steps, else: 0.0),
      avg_calls_per_step: if(orch.total_steps > 0, do: orch.total_llm_calls / orch.total_steps, else: 0.0),
      k: orch.k,
      score_threshold: orch.score_threshold
    }
  end

  # ── 内部：首候选达标 ──

  defp handle_accepted(orch, response, candidate, score, action, step_num) do
    telemetry = %{
      step: step_num,
      upgraded: false,
      llm_calls: 1,
      first_score: score,
      final_score: score,
      final_action: action,
      threshold: orch.score_threshold,
      all_scores: [score],
      fallback_used: false
    }

    emit_telemetry(telemetry)

    # 更新 selector scorer_state（标记 action 已执行）
    updated_selector = PhiCandidateSelector.update_after_execution(orch.selector, action)

    updated_orch = %{orch |
      selector: updated_selector,
      total_steps: step_num,
      total_llm_calls: orch.total_llm_calls + 1
    }

    {:ok, response, updated_orch, telemetry}
  end

  # ── 内部：升级到 Best-of-K ──

  defp handle_upgrade(orch, agent, call_id, llm_backend, first_response, first_candidate, first_score, step_num) do
    extra_k = orch.k - 1

    # 并发生成 K-1 个额外候选
    extra_results = generate_extra_candidates(agent, call_id, llm_backend, extra_k)

    # 过滤成功的
    extra_responses =
      extra_results
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, resp} -> resp end)

    # 合并所有候选（首候选 + 额外候选）
    all_responses = [first_response | extra_responses]

    # 对所有候选解析 + 打分
    all_scored = score_all_responses(all_responses, orch.selector)
    parsed = Enum.filter(all_scored, fn c -> c.score_result != nil end)

    total_calls = 1 + extra_k

    case parsed do
      [] ->
        # 所有候选都解析失败 → 回退首候选
        telemetry = %{
          step: step_num,
          upgraded: true,
          llm_calls: total_calls,
          first_score: first_score,
          final_score: nil,
          final_action: nil,
          threshold: orch.score_threshold,
          all_scores: [],
          fallback_used: true
        }

        emit_telemetry(telemetry)

        updated_orch = %{orch |
          total_steps: step_num,
          upgraded_steps: orch.upgraded_steps + 1,
          total_llm_calls: orch.total_llm_calls + total_calls
        }

        {:ok, first_response, updated_orch, telemetry}

      candidates ->
        # 按分数排序，同分取更短 response
        sorted =
          Enum.sort_by(candidates, fn c ->
            {-c.score_result.score, byte_size(c.raw_text || "")}
          end)

        best = hd(sorted)
        all_scores = Enum.map(candidates, fn c -> c.score_result.score end)

        telemetry = %{
          step: step_num,
          upgraded: true,
          llm_calls: total_calls,
          first_score: first_score,
          final_score: best.score_result.score,
          final_action: best.action,
          threshold: orch.score_threshold,
          all_scores: all_scores,
          fallback_used: false
        }

        emit_telemetry(telemetry)

        # 更新 selector scorer_state
        updated_selector = PhiCandidateSelector.update_after_execution(orch.selector, best.action)

        updated_orch = %{orch |
          selector: updated_selector,
          total_steps: step_num,
          upgraded_steps: orch.upgraded_steps + 1,
          total_llm_calls: orch.total_llm_calls + total_calls
        }

        {:ok, best.response, updated_orch, telemetry}
    end
  end

  # ── 候选生成 ──

  defp generate_first_candidate(agent, call_id, llm_backend) do
    case llm_backend.(agent, call_id) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:ok, other}
    end
  end

  defp generate_extra_candidates(agent, call_id, llm_backend, count) when count <= 0, do: []

  defp generate_extra_candidates(agent, call_id, llm_backend, count) do
    timeout = 120_000

    1..count
    |> Task.async_stream(
      fn _i -> llm_backend.(agent, call_id) end,
      max_concurrency: min(count, 8),
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, {:ok, _} = result} -> result
      {:ok, {:error, _} = err} -> err
      {:ok, other} -> {:ok, other}
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, reason}
    end)
  end

  # ── 打分 ──

  defp score_response(response, selector) do
    raw_text = extract_text(response)

    case PhiCandidateSelector.parse_action(raw_text) do
      {:ok, action, _content, _thought} ->
        score_result = do_score(selector, action)

        if score_result do
          {:ok, score_result.score, action, %{response: response, action: action, score_result: score_result, raw_text: raw_text}}
        else
          :parse_failed
        end

      :parse_failed ->
        :parse_failed
    end
  end

  defp score_all_responses(responses, selector) do
    Enum.map(responses, fn response ->
      raw_text = extract_text(response)

      case PhiCandidateSelector.parse_action(raw_text) do
        {:ok, action, content, thought} ->
          score_result = do_score(selector, action)

          %{
            response: response,
            action: action,
            content: content,
            thought: thought,
            score_result: score_result,
            raw_text: raw_text
          }

        :parse_failed ->
          %{
            response: response,
            action: nil,
            content: nil,
            thought: nil,
            score_result: nil,
            raw_text: raw_text
          }
      end
    end)
  end

  defp do_score(selector, action) do
    # 复用 selector 内部的打分逻辑
    # PhiCandidateSelector 的 scorer 通过 UniboVariationCenter.PhiCandidateScorer 或内联打分
    if Code.ensure_loaded?(UniboVariationCenter.PhiCandidateScorer) do
      UniboVariationCenter.PhiCandidateScorer.score_candidate_action(
        selector.scorer_state,
        action,
        selector.phi_id
      )
    else
      inline_score(selector.scorer_state, action)
    end
  end

  # 轻量级内联打分（与 PhiCandidateSelector 一致）
  defp inline_score(scorer_state, action) do
    score =
      cond do
        scorer_state.step_num == 0 and action in ["READ_CODE", "READ_TESTS"] -> 2.0
        scorer_state.last_action == "PATCH" and action == "RUN_TESTS" -> 3.0
        scorer_state.last_test_result == false and action in ["READ_CODE", "READ_TESTS"] -> 2.0
        scorer_state.consecutive_same_action >= 1 -> -1.5 * scorer_state.consecutive_same_action
        true -> 0.5
      end

    %{
      score: score,
      positions: %{},
      judgments: [],
      reasons: ["inline fallback"],
      candidate_action: action
    }
  end

  # ── 文本提取 ──

  defp extract_text({:ok, text}) when is_binary(text), do: text
  defp extract_text({:text, text}) when is_binary(text), do: text
  defp extract_text({:tool_calls, _}), do: nil
  defp extract_text({:error, _}), do: nil
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(_), do: nil

  # ── Telemetry ──

  defp emit_telemetry(telemetry) do
    :telemetry.execute(
      [:gong, :phi, :hybrid],
      %{
        llm_calls: telemetry.llm_calls,
        first_score: telemetry.first_score || 0.0,
        final_score: telemetry.final_score || 0.0
      },
      %{
        step: telemetry.step,
        upgraded: telemetry.upgraded,
        threshold: telemetry.threshold,
        final_action: telemetry.final_action,
        all_scores: telemetry.all_scores,
        fallback_used: telemetry.fallback_used
      }
    )
  end
end
