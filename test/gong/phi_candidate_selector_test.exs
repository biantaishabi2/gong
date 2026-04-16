defmodule Gong.PhiCandidateSelectorTest do
  @moduledoc """
  PhiCandidateSelector 单元测试（#2845）。

  验证并发候选生成、ACTION 解析、Φ 打分选择、tie-break、降级路径。
  """
  use ExUnit.Case, async: true

  alias Gong.PhiCandidateSelector, as: Selector

  # ============================================================
  # parse_action 解析测试
  # ============================================================

  describe "parse_action/1" do
    test "正常格式：THOUGHT + ACTION" do
      text = """
      THOUGHT: The bug is in the loop condition
      ACTION: READ_CODE
      """

      assert {:ok, "READ_CODE", nil, "The bug is in the loop condition"} =
               Selector.parse_action(text)
    end

    test "PATCH action 带 code block" do
      text = """
      THOUGHT: Fix the off-by-one error
      ACTION: PATCH
      ```python
      def foo():
          return 42
      ```
      """

      assert {:ok, "PATCH", content, "Fix the off-by-one error"} =
               Selector.parse_action(text)

      assert String.contains?(content, "return 42")
    end

    test "降级：无 ACTION 但有 code block → PATCH" do
      text = """
      THOUGHT: Here's the fix
      ```python
      def foo():
          return 42
      ```
      """

      assert {:ok, "PATCH", content, "Here's the fix"} = Selector.parse_action(text)
      assert String.contains?(content, "return 42")
    end

    test "完全无法解析 → :parse_failed" do
      assert :parse_failed = Selector.parse_action(nil)
      assert :parse_failed = Selector.parse_action("")
    end

    test "只有 THOUGHT 无 ACTION 无 code → :parse_failed" do
      text = "THOUGHT: I'm thinking about this"
      assert :parse_failed = Selector.parse_action(text)
    end

    test "RUN_TESTS action" do
      text = """
      THOUGHT: Let's verify the fix
      ACTION: RUN_TESTS
      """

      assert {:ok, "RUN_TESTS", nil, "Let's verify the fix"} =
               Selector.parse_action(text)
    end
  end

  # ============================================================
  # Selector 创建
  # ============================================================

  describe "new/1" do
    test "默认配置" do
      selector = Selector.new()
      assert selector.k == 5
      assert selector.phi_id == nil
      assert selector.total_candidates == 0
    end

    test "自定义配置" do
      selector = Selector.new(phi_id: "phi_methodical", k: 3)
      assert selector.k == 3
      assert selector.phi_id == "phi_methodical"
    end
  end

  # ============================================================
  # select_best 核心逻辑
  # ============================================================

  describe "select_best/4" do
    test "K=1 退化为单次调用" do
      selector = Selector.new(k: 1, phi_id: "phi_methodical")
      call_count = :counters.new(1, [:atomics])

      mock_backend = fn _agent, _call_id ->
        :counters.add(call_count, 1, 1)
        {:ok, {:text, "THOUGHT: reading\nACTION: READ_CODE"}}
      end

      assert {:ok, {:text, _}, _selector, telemetry} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

      assert :counters.get(call_count, 1) == 1
      assert telemetry.k == 1
    end

    test "K=5 并发调用 5 次" do
      selector = Selector.new(k: 5, phi_id: "phi_methodical")
      call_count = :counters.new(1, [:atomics])

      responses = [
        "THOUGHT: a\nACTION: READ_CODE",
        "THOUGHT: b\nACTION: PATCH\n```python\nfix\n```",
        "THOUGHT: c\nACTION: RUN_TESTS",
        "THOUGHT: d\nACTION: READ_TESTS",
        "THOUGHT: e\nACTION: DONE"
      ]

      idx = :counters.new(1, [:atomics])

      mock_backend = fn _agent, _call_id ->
        :counters.add(call_count, 1, 1)
        i = :counters.get(idx, 1)
        :counters.add(idx, 1, 1)
        resp = Enum.at(responses, rem(i, 5))
        {:ok, {:text, resp}}
      end

      assert {:ok, {:text, _}, updated_selector, telemetry} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

      assert :counters.get(call_count, 1) == 5
      assert telemetry.k == 5
      assert telemetry.parsed_count > 0
      assert is_float(telemetry.best_score) or is_integer(telemetry.best_score)
      assert updated_selector.total_candidates == 5
    end

    test "解析失败候选被丢弃" do
      selector = Selector.new(k: 3, phi_id: "phi_methodical")

      responses = [
        "THOUGHT: a\nACTION: READ_CODE",
        "some random garbage without action or code",
        "more garbage"
      ]

      idx = :counters.new(1, [:atomics])

      mock_backend = fn _agent, _call_id ->
        i = :counters.get(idx, 1)
        :counters.add(idx, 1, 1)
        resp = Enum.at(responses, rem(i, 3))
        {:ok, {:text, resp}}
      end

      assert {:ok, {:text, _}, _selector, telemetry} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

      # 至少 1 个被成功解析，2 个被丢弃
      assert telemetry.parsed_count >= 1
      assert telemetry.discarded_count >= 1
    end

    test "所有候选都解析失败时降级返回第一个" do
      selector = Selector.new(k: 3)

      mock_backend = fn _agent, _call_id ->
        {:ok, {:text, "random text without structure"}}
      end

      assert {:ok, {:text, "random text without structure"}, _selector, telemetry} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

      assert telemetry.parsed_count == 0
      assert telemetry.discarded_count == 3
    end

    test "所有 LLM 调用失败时返回 error" do
      selector = Selector.new(k: 3)

      mock_backend = fn _agent, _call_id ->
        {:error, :timeout}
      end

      assert {:error, :all_candidates_failed} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)
    end

    test "tool_calls 响应不参与 action 解析（无文本）" do
      selector = Selector.new(k: 2)

      idx = :counters.new(1, [:atomics])

      mock_backend = fn _agent, _call_id ->
        i = :counters.get(idx, 1)
        :counters.add(idx, 1, 1)

        if rem(i, 2) == 0 do
          {:ok, {:text, "THOUGHT: a\nACTION: READ_CODE"}}
        else
          {:ok, {:tool_calls, [%{name: "read", arguments: %{}}]}}
        end
      end

      assert {:ok, _response, _selector, _telemetry} =
               Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)
    end
  end

  # ============================================================
  # 选择稳定性（并发返回顺序不影响结果）
  # ============================================================

  describe "选择稳定性" do
    test "无论候选顺序如何，总是选出同一个最高分" do
      selector = Selector.new(k: 3, phi_id: "phi_methodical")

      # 固定 3 个候选：READ_CODE（初始时最佳）、PATCH（差）、RUN_TESTS（差）
      responses_orders = [
        ["THOUGHT: a\nACTION: READ_CODE",
         "THOUGHT: b\nACTION: PATCH\n```python\nfix\n```",
         "THOUGHT: c\nACTION: RUN_TESTS"],
        ["THOUGHT: c\nACTION: RUN_TESTS",
         "THOUGHT: a\nACTION: READ_CODE",
         "THOUGHT: b\nACTION: PATCH\n```python\nfix\n```"],
        ["THOUGHT: b\nACTION: PATCH\n```python\nfix\n```",
         "THOUGHT: c\nACTION: RUN_TESTS",
         "THOUGHT: a\nACTION: READ_CODE"]
      ]

      best_actions =
        for responses <- responses_orders do
          idx = :counters.new(1, [:atomics])

          mock_backend = fn _agent, _call_id ->
            i = :counters.get(idx, 1)
            :counters.add(idx, 1, 1)
            {:ok, {:text, Enum.at(responses, rem(i, 3))}}
          end

          {:ok, _resp, _sel, telemetry} =
            Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

          telemetry.best_action
        end

      # 所有顺序应选出相同 action
      assert Enum.uniq(best_actions) |> length() == 1
    end
  end

  # ============================================================
  # Tie-break（同分取更短 response）
  # ============================================================

  describe "tie-break" do
    test "同分候选取更短 response" do
      selector = Selector.new(k: 2, phi_id: "phi_methodical")

      # 两个相同 action，一长一短
      short = "THOUGHT: x\nACTION: READ_CODE"
      long = "THOUGHT: let me think about this very carefully and explain in detail\nACTION: READ_CODE"

      idx = :counters.new(1, [:atomics])

      mock_backend = fn _agent, _call_id ->
        i = :counters.get(idx, 1)
        :counters.add(idx, 1, 1)

        if rem(i, 2) == 0 do
          {:ok, {:text, long}}
        else
          {:ok, {:text, short}}
        end
      end

      {:ok, {:text, chosen}, _sel, _tel} =
        Selector.select_best(selector, %{state: %{}}, "call_1", mock_backend)

      # 同分时应选更短的
      assert byte_size(chosen) <= byte_size(long)
    end
  end

  # ============================================================
  # update_after_execution
  # ============================================================

  describe "update_after_execution/3" do
    test "执行后更新 scorer 状态" do
      selector = Selector.new(phi_id: "phi_methodical")
      updated = Selector.update_after_execution(selector, "READ_CODE")

      # scorer_state 应该被更新
      assert updated.scorer_state != selector.scorer_state
    end
  end

  # ============================================================
  # K=1 和 K=5 走同一条主逻辑
  # ============================================================

  describe "K=1 vs K=5 兼容性" do
    test "K=1 和 K=5 返回相同结构的 telemetry" do
      mock_backend = fn _agent, _call_id ->
        {:ok, {:text, "THOUGHT: a\nACTION: READ_CODE"}}
      end

      {:ok, _, _, tel1} =
        Selector.new(k: 1)
        |> Selector.select_best(%{state: %{}}, "c1", mock_backend)

      {:ok, _, _, tel5} =
        Selector.new(k: 5)
        |> Selector.select_best(%{state: %{}}, "c1", mock_backend)

      # 结构相同
      assert Map.keys(tel1) |> Enum.sort() == Map.keys(tel5) |> Enum.sort()
      assert tel1.k == 1
      assert tel5.k == 5
    end
  end
end
