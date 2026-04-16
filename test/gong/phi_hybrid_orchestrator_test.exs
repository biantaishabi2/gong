defmodule Gong.PhiHybridOrchestratorTest do
  use ExUnit.Case, async: true

  alias Gong.PhiHybridOrchestrator

  # ── 辅助函数 ──

  # 构造一个返回指定 ACTION 文本的 LLM backend
  defp make_backend(action, opts \\ []) do
    thought = Keyword.get(opts, :thought, "thinking...")
    fn _agent, _call_id ->
      {:ok, "THOUGHT: #{thought}\nACTION: #{action}"}
    end
  end

  # 构造一个会失败的 LLM backend
  defp failing_backend do
    fn _agent, _call_id ->
      {:error, :llm_failure}
    end
  end

  # 构造一个返回无法解析内容的 LLM backend
  defp unparseable_backend do
    fn _agent, _call_id ->
      {:ok, "some random text without action marker"}
    end
  end

  # 构造一个首次返回低分、后续返回高分的 backend
  # 使用 Agent 跨进程共享计数器（Task.async_stream 在独立进程执行）
  defp escalating_backend do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    fn _agent, _call_id ->
      count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if count == 0 do
        # 首候选：PATCH（在 step 0 得分低 = 0.5）
        {:ok, "THOUGHT: trying patch\nACTION: PATCH"}
      else
        # 额外候选：READ_CODE（在 step 0 得分高 = 2.0）
        {:ok, "THOUGHT: reading code\nACTION: READ_CODE"}
      end
    end
  end

  defp dummy_agent, do: %{name: "test"}

  # ── 测试：不升级路径 ──

  describe "不升级（首候选达标）" do
    test "首候选分数 >= threshold → 直接使用，1× 调用" do
      # READ_CODE 在 step 0 得分 2.0，threshold 1.0 → 达标
      orch = PhiHybridOrchestrator.new(k: 5, score_threshold: 1.0)
      backend = make_backend("READ_CODE")

      assert {:ok, response, updated_orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      # 验证响应（orchestrator 透传 backend 返回值）
      assert is_binary(response) or match?({:ok, _}, response)

      # 验证 telemetry
      assert telemetry.upgraded == false
      assert telemetry.llm_calls == 1
      assert telemetry.first_score == 2.0
      assert telemetry.final_score == 2.0
      assert telemetry.final_action == "READ_CODE"
      assert telemetry.fallback_used == false

      # 验证累计统计
      assert updated_orch.total_steps == 1
      assert updated_orch.upgraded_steps == 0
      assert updated_orch.total_llm_calls == 1
    end

    test "多步不升级 → 总调用数 = 步数" do
      # threshold 极低确保不升级（连续相同 action 分数会降为负数）
      orch = PhiHybridOrchestrator.new(k: 5, score_threshold: -100.0)
      backend = make_backend("READ_CODE")

      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c1", backend)
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c2", backend)
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c3", backend)

      summary = PhiHybridOrchestrator.summary(orch)
      assert summary.total_steps == 3
      assert summary.upgraded_steps == 0
      assert summary.total_llm_calls == 3
      assert summary.upgrade_rate == 0.0
      assert summary.avg_calls_per_step == 1.0
    end
  end

  # ── 测试：升级路径 ──

  describe "升级（首候选不达标）" do
    test "首候选分数 < threshold → 升级生成 K-1 个额外候选" do
      # 设 threshold 很高，PATCH 在 step 0 得分 0.5 → 不达标 → 升级
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 10.0)
      backend = escalating_backend()

      assert {:ok, _response, updated_orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      # 验证升级发生
      assert telemetry.upgraded == true
      assert telemetry.llm_calls == 3
      assert telemetry.first_score == 0.5
      # 升级后应选 READ_CODE（分数 2.0 > PATCH 0.5）
      assert telemetry.final_action == "READ_CODE"
      assert telemetry.final_score == 2.0

      # 验证累计统计
      assert updated_orch.total_steps == 1
      assert updated_orch.upgraded_steps == 1
      assert updated_orch.total_llm_calls == 3
    end

    test "首候选解析失败 → 直接升级" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      backend = fn _agent, _call_id ->
        count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if count == 0 do
          # 首候选无法解析
          {:ok, "gibberish without action"}
        else
          # 额外候选可以解析
          {:ok, "THOUGHT: ok\nACTION: READ_CODE"}
        end
      end

      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 1.0)

      assert {:ok, _response, updated_orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      assert telemetry.upgraded == true
      # 首候选解析失败 → first_score 为 nil
      assert telemetry.first_score == nil
    end
  end

  # ── 测试：部分失败 ──

  describe "部分失败处理" do
    test "额外候选部分失败 → 用剩余候选继续选择" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      backend = fn _agent, _call_id ->
        count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        case count do
          0 -> {:ok, "THOUGHT: low\nACTION: PATCH"}
          1 -> {:error, :timeout}
          _ -> {:ok, "THOUGHT: good\nACTION: READ_CODE"}
        end
      end

      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 10.0)

      assert {:ok, _response, _updated_orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      # 应该升级且成功（即使 1 个候选超时）
      assert telemetry.upgraded == true
      # 至少有 parsed candidates
      assert length(telemetry.all_scores) >= 1
    end

    test "所有额外候选都解析失败 → 回退首候选" do
      {:ok, counter} = Agent.start_link(fn -> 0 end)

      backend = fn _agent, _call_id ->
        count = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

        if count == 0 do
          {:ok, "THOUGHT: low\nACTION: PATCH"}
        else
          {:ok, "gibberish no action here"}
        end
      end

      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 10.0)

      assert {:ok, response, _updated_orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      # 回退到首候选
      assert telemetry.upgraded == true
      assert telemetry.fallback_used == false
      # 首候选的 PATCH 仍可解析 → final_action 应为 PATCH
      assert telemetry.final_action == "PATCH"
    end
  end

  # ── 测试：回退路径 ──

  describe "回退路径" do
    test "LLM 完全失败 → 返回 error" do
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 1.0)
      backend = failing_backend()

      assert {:error, :llm_failure} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)
    end

    test "首候选无法解析 + 所有额外候选也无法解析 → 回退首候选" do
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 1.0)
      backend = unparseable_backend()

      assert {:ok, response, _orch, telemetry} =
               PhiHybridOrchestrator.run_step(orch, dummy_agent(), "call_1", backend)

      # 使用了 fallback
      assert telemetry.fallback_used == true
      assert telemetry.upgraded == true
      assert telemetry.all_scores == []
    end
  end

  # ── 测试：成本统计 ──

  describe "成本统计" do
    test "混合策略比纯 Best-of-K 省成本（简单场景）" do
      # 简单场景：首候选就达标 → 1× 成本
      orch = PhiHybridOrchestrator.new(k: 5, score_threshold: 0.0)
      backend = make_backend("READ_CODE")

      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c1", backend)
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c2", backend)
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c3", backend)

      summary = PhiHybridOrchestrator.summary(orch)

      # 混合策略 3 次调用 vs 纯 Best-of-K 15 次调用（K=5, 3 步）
      pure_best_of_k_calls = summary.k * summary.total_steps
      assert summary.total_llm_calls < pure_best_of_k_calls * 0.5
    end

    test "summary 正确反映升级率" do
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 10.0)
      backend = make_backend("PATCH")

      # 所有步骤都会升级（threshold 很高）
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c1", backend)
      {:ok, _, orch, _} = PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c2", backend)

      summary = PhiHybridOrchestrator.summary(orch)
      assert summary.upgrade_rate == 1.0
      assert summary.total_llm_calls == 6
    end
  end

  # ── 测试：可配置阈值 ──

  describe "阈值配置" do
    test "threshold = 0 → 几乎不升级" do
      orch = PhiHybridOrchestrator.new(k: 5, score_threshold: -100.0)
      backend = make_backend("PATCH")

      {:ok, _, orch, telemetry} =
        PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c1", backend)

      assert telemetry.upgraded == false
      assert orch.total_llm_calls == 1
    end

    test "threshold 很高 → 总是升级" do
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 999.0)
      backend = make_backend("READ_CODE")

      {:ok, _, orch, telemetry} =
        PhiHybridOrchestrator.run_step(orch, dummy_agent(), "c1", backend)

      assert telemetry.upgraded == true
      assert orch.total_llm_calls == 3
    end
  end

  # ── 测试：update_after_execution ──

  describe "update_after_execution" do
    test "更新 scorer 状态" do
      orch = PhiHybridOrchestrator.new(k: 3, score_threshold: 1.0)
      updated = PhiHybridOrchestrator.update_after_execution(orch, "PATCH")

      assert updated.selector.scorer_state.last_action == "PATCH"
      assert updated.selector.scorer_state.step_num == 1
    end
  end
end
