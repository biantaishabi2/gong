defmodule Gong.PhiCandidateSelector do
  @moduledoc """
  Φ Best-of-K 候选选择器（#2845）。

  生成 K 个并发 LLM 候选 → 解析 ACTION → Φ(state, action) 打分 → 选最高分。

  ## 使用方式

  作为 AgentLoop 的包装层，不改变 AgentLoop 内部逻辑：

      # 在 drive_loop 的 LLM 调用处，用 selector 替代单次调用
      selector = PhiCandidateSelector.new(phi_id: "phi_methodical", k: 5)
      {best_response, selector, telemetry} =
        PhiCandidateSelector.select_best(selector, agent, call_id, llm_backend)

  ## 设计决策

  - 解析失败的候选直接丢弃，不参与打分
  - 全部候选都低分时仍强选最高分（不拒绝）
  - 同分时 tie-break：选更短的 response（更简洁 = 更确定）
  - telemetry 记录所有候选的分数分布
  - K=1 时退化为普通单次调用
  """

  require Logger

  @type t :: %__MODULE__{
          phi_id: String.t() | nil,
          k: pos_integer(),
          scorer_state: map(),
          total_candidates: non_neg_integer(),
          total_discarded: non_neg_integer()
        }

  defstruct phi_id: nil,
            k: 5,
            scorer_state: nil,
            total_candidates: 0,
            total_discarded: 0

  @type candidate :: %{
          response: term(),
          action: String.t(),
          content: String.t() | nil,
          thought: String.t(),
          score_result: map() | nil,
          raw_text: String.t() | nil
        }

  @type selection_telemetry :: %{
          k: pos_integer(),
          parsed_count: non_neg_integer(),
          discarded_count: non_neg_integer(),
          scores: [float()],
          actions: [String.t()],
          best_score: float(),
          best_action: String.t()
        }

  @doc "创建新的选择器。"
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      phi_id: Keyword.get(opts, :phi_id),
      k: Keyword.get(opts, :k, 5),
      scorer_state: new_scorer_state()
    }
  end

  @doc """
  并发生成 K 个候选，解析 ACTION，Φ 打分，选最高分。

  返回 `{best_response, updated_selector, telemetry}`。
  - best_response: 被选中的 LLM 响应（格式同 llm_backend 返回值）
  - updated_selector: 更新了 scorer_state 的选择器
  - telemetry: 本次选择的诊断数据

  如果所有候选都解析失败，返回第一个原始响应（降级）。
  """
  @spec select_best(t(), struct(), String.t(), function()) ::
          {:ok, term(), t(), selection_telemetry()} | {:error, term()}
  def select_best(%__MODULE__{k: k} = selector, agent, call_id, llm_backend) do
    # 并发生成 K 个候选
    candidates = generate_candidates(agent, call_id, llm_backend, k)

    # 过滤 LLM 调用失败
    {ok_candidates, _errors} =
      Enum.split_with(candidates, fn
        {:ok, _response} -> true
        {:error, _} -> false
      end)

    ok_responses = Enum.map(ok_candidates, fn {:ok, resp} -> resp end)

    if ok_responses == [] do
      # 全部 LLM 调用失败
      {:error, :all_candidates_failed}
    else
      # 解析并打分
      scored = parse_and_score(ok_responses, selector)

      {parsed, discarded} =
        Enum.split_with(scored, fn c -> c.score_result != nil end)

      if parsed == [] do
        # 所有候选都解析失败，降级用第一个
        first_resp = hd(ok_responses)
        telemetry_data = build_telemetry(selector.k, [], discarded)

        emit_telemetry(telemetry_data)

        {:ok, first_resp,
         %{selector |
           total_candidates: selector.total_candidates + length(ok_responses),
           total_discarded: selector.total_discarded + length(discarded)
         }, telemetry_data}
      else
        # 按分数排序，同分取更短 response
        sorted =
          Enum.sort_by(parsed, fn c ->
            {-c.score_result.score, byte_size(c.raw_text || "")}
          end)

        best = hd(sorted)
        telemetry_data = build_telemetry(selector.k, parsed, discarded)

        emit_telemetry(telemetry_data)

        # 更新 scorer state（记录被选中的 action 已执行）
        updated_scorer =
          update_scorer_state(selector.scorer_state, best.action)

        {:ok, best.response,
         %{selector |
           scorer_state: updated_scorer,
           total_candidates: selector.total_candidates + length(ok_responses),
           total_discarded: selector.total_discarded + length(discarded)
         }, telemetry_data}
      end
    end
  end

  @doc """
  在 action 执行后更新 scorer 状态（例如 RUN_TESTS 后更新 test_passed）。
  """
  @spec update_after_execution(t(), String.t(), keyword()) :: t()
  def update_after_execution(%__MODULE__{} = selector, action, opts \\ []) do
    updated = update_scorer_state(selector.scorer_state, action, opts)
    %{selector | scorer_state: updated}
  end

  # ── 并发候选生成 ──

  defp generate_candidates(agent, call_id, llm_backend, k) when k <= 1 do
    [llm_backend.(agent, call_id)]
  end

  defp generate_candidates(agent, call_id, llm_backend, k) do
    # OTP Task.async_stream 并发调用
    timeout = 120_000

    1..k
    |> Task.async_stream(
      fn _i -> llm_backend.(agent, call_id) end,
      max_concurrency: min(k, 8),
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> {:error, :timeout}
      {:exit, reason} -> {:error, reason}
    end)
  end

  # ── 解析 + 打分 ──

  defp parse_and_score(responses, %__MODULE__{phi_id: phi_id, scorer_state: scorer_state}) do
    Enum.map(responses, fn response ->
      raw_text = extract_text(response)

      case parse_action(raw_text) do
        {:ok, action, content, thought} ->
          score_result = score_candidate(scorer_state, action, phi_id)

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

  @doc """
  解析 LLM 响应文本为 (action, content, thought)。

  降级规则：
  - 有 ACTION: 标记 → 使用该 action
  - 无 ACTION: 但有 code block → 视为 PATCH
  - 完全无法解析 → :parse_failed
  """
  @spec parse_action(String.t() | nil) :: {:ok, String.t(), String.t() | nil, String.t()} | :parse_failed
  def parse_action(nil), do: :parse_failed

  def parse_action(text) when is_binary(text) do
    lines = String.split(text, "\n")

    thought =
      Enum.find_value(lines, "", fn line ->
        if String.starts_with?(line, "THOUGHT:") do
          line |> String.slice(8..-1//1) |> String.trim()
        end
      end)

    action =
      Enum.find_value(lines, nil, fn line ->
        if String.starts_with?(line, "ACTION:") do
          line |> String.slice(7..-1//1) |> String.trim()
        end
      end)

    code_blocks = Regex.scan(~r/```(?:python|elixir)?\n(.*?)```/s, text, capture: :all_but_first)
    code_block = case code_blocks do
      [] -> nil
      blocks -> blocks |> List.last() |> hd()
    end

    cond do
      action != nil and action != "" ->
        content = if action == "PATCH", do: code_block, else: nil
        {:ok, action, content, thought}

      code_block != nil ->
        # 降级：无 ACTION 但有 code block → PATCH
        {:ok, "PATCH", code_block, thought}

      thought != "" ->
        # 有 THOUGHT 但没有 ACTION 也没有 code block → 无法确定 action
        :parse_failed

      true ->
        :parse_failed
    end
  end

  # ── Scorer 调用 ──

  # 调用 unibo_variation_center_runtime 的 PhiCandidateScorer（如果可用）
  # 否则用内联的轻量级打分
  defp score_candidate(scorer_state, action, phi_id) do
    if Code.ensure_loaded?(UniboVariationCenter.PhiCandidateScorer) do
      UniboVariationCenter.PhiCandidateScorer.score_candidate_action(
        scorer_state,
        action,
        phi_id
      )
    else
      # 轻量级内联打分（不依赖 unibo_variation_center_runtime）
      inline_score(scorer_state, action, phi_id)
    end
  end

  defp new_scorer_state do
    if Code.ensure_loaded?(UniboVariationCenter.PhiCandidateScorer) do
      UniboVariationCenter.PhiCandidateScorer.new()
    else
      %{
        step_num: 0,
        last_action: nil,
        consecutive_same_action: 0,
        patch_count: 0,
        test_count: 0,
        read_count: 0,
        history: [],
        last_test_result: nil,
        has_read_code: false,
        has_read_tests: false,
        last_patch_failed: false
      }
    end
  end

  defp update_scorer_state(scorer_state, action, opts \\ []) do
    if Code.ensure_loaded?(UniboVariationCenter.PhiCandidateScorer) do
      UniboVariationCenter.PhiCandidateScorer.update(scorer_state, action, opts)
    else
      # 轻量内联状态更新
      consecutive =
        if action == scorer_state.last_action,
          do: scorer_state.consecutive_same_action + 1,
          else: 0

      scorer_state
      |> Map.merge(%{
        step_num: scorer_state.step_num + 1,
        last_action: action,
        consecutive_same_action: consecutive,
        history: scorer_state.history ++ [action]
      })
    end
  end

  # 轻量级内联打分（不依赖外部模块，简化版 5 位打分）
  defp inline_score(scorer_state, action, _phi_id) do
    score =
      cond do
        # 首步倾向 READ
        scorer_state.step_num == 0 and action in ["READ_CODE", "READ_TESTS"] -> 2.0
        # PATCH 后倾向 RUN_TESTS
        scorer_state.last_action == "PATCH" and action == "RUN_TESTS" -> 3.0
        # 测试失败后倾向 READ
        scorer_state.last_test_result == false and action in ["READ_CODE", "READ_TESTS"] -> 2.0
        # 连续相同 action 扣分
        scorer_state.consecutive_same_action >= 1 -> -1.5 * scorer_state.consecutive_same_action
        # 默认
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

  defp extract_text({:text, text}) when is_binary(text), do: text
  defp extract_text({:tool_calls, _}), do: nil
  defp extract_text({:error, _}), do: nil
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(_), do: nil

  # ── Telemetry ──

  defp build_telemetry(k, parsed, discarded) do
    scores = Enum.map(parsed, fn c -> c.score_result.score end)
    actions = Enum.map(parsed, fn c -> c.action end)

    {best_score, best_action} =
      case parsed do
        [] -> {0.0, "none"}
        _ ->
          best = hd(Enum.sort_by(parsed, fn c -> -c.score_result.score end))
          {best.score_result.score, best.action}
      end

    %{
      k: k,
      parsed_count: length(parsed),
      discarded_count: length(discarded),
      scores: scores,
      actions: actions,
      best_score: best_score,
      best_action: best_action
    }
  end

  defp emit_telemetry(telemetry_data) do
    :telemetry.execute(
      [:gong, :phi, :best_of_k],
      %{
        best_score: telemetry_data.best_score,
        parsed_count: telemetry_data.parsed_count,
        discarded_count: telemetry_data.discarded_count
      },
      %{
        k: telemetry_data.k,
        scores: telemetry_data.scores,
        actions: telemetry_data.actions,
        best_action: telemetry_data.best_action
      }
    )
  end
end
