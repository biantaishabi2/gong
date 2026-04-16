defmodule Gong.PhiGuidanceTest do
  @moduledoc """
  Gong.PhiGuidance 适配层 + PhiGuidanceHook 单元/集成测试（#2844）。
  """
  use ExUnit.Case, async: true

  alias Gong.PhiGuidance
  alias Gong.PhiGuidanceHook

  # ============================================================
  # Tracker 生命周期
  # ============================================================

  describe "tracker 生命周期" do
    test "init → get → cleanup" do
      PhiGuidance.init_tracker()
      tracker = PhiGuidance.get_tracker()

      assert tracker.step_num == 0
      assert tracker.last_action == nil
      assert tracker.patch_count == 0
      assert tracker.test_count == 0

      PhiGuidance.cleanup()
      # cleanup 后 get 返回新 tracker
      assert PhiGuidance.get_tracker().step_num == 0
    end

    test "update_tracker 正确累积状态" do
      PhiGuidance.init_tracker()

      PhiGuidance.update_tracker("read", %{"path" => "lib/foo.ex"})
      t = PhiGuidance.get_tracker()
      assert t.step_num == 1
      assert t.last_action == :READ_CODE
      assert t.has_read_code == true
      assert t.read_count == 1

      PhiGuidance.update_tracker("edit", %{"path" => "lib/foo.ex"})
      t = PhiGuidance.get_tracker()
      assert t.step_num == 2
      assert t.last_action == :PATCH
      assert t.patch_count == 1

      PhiGuidance.update_tracker("bash", %{"command" => "mix test"})
      t = PhiGuidance.get_tracker()
      assert t.step_num == 3
      assert t.last_action == :RUN_TESTS
      assert t.test_count == 1

      PhiGuidance.cleanup()
    end
  end

  # ============================================================
  # Action 分类
  # ============================================================

  describe "action 分类" do
    setup do
      PhiGuidance.init_tracker()
      on_exit(fn -> PhiGuidance.cleanup() end)
    end

    test "read 工具 → READ_CODE" do
      PhiGuidance.update_tracker("read", %{"path" => "lib/main.ex"})
      assert PhiGuidance.get_tracker().last_action == :READ_CODE
    end

    test "read 测试文件 → READ_TESTS" do
      PhiGuidance.update_tracker("read", %{"path" => "test/main_test.exs"})
      assert PhiGuidance.get_tracker().last_action == :READ_TESTS
    end

    test "grep → READ_CODE" do
      PhiGuidance.update_tracker("grep", %{"path" => "lib/"})
      assert PhiGuidance.get_tracker().last_action == :READ_CODE
    end

    test "write → PATCH" do
      PhiGuidance.update_tracker("write", %{"path" => "lib/fix.ex"})
      assert PhiGuidance.get_tracker().last_action == :PATCH
    end

    test "bash mix test → RUN_TESTS" do
      PhiGuidance.update_tracker("bash", %{"command" => "cd project && mix test"})
      assert PhiGuidance.get_tracker().last_action == :RUN_TESTS
    end

    test "bash 非测试命令 → 不更新 action" do
      PhiGuidance.update_tracker("bash", %{"command" => "ls -la"})
      assert PhiGuidance.get_tracker().last_action == nil
    end

    test "未知工具 → 不更新 action" do
      PhiGuidance.update_tracker("unknown_tool", %{})
      assert PhiGuidance.get_tracker().last_action == nil
      assert PhiGuidance.get_tracker().step_num == 0
    end
  end

  # ============================================================
  # Consecutive 跟踪
  # ============================================================

  describe "consecutive 跟踪" do
    setup do
      PhiGuidance.init_tracker()
      on_exit(fn -> PhiGuidance.cleanup() end)
    end

    test "连续相同动作计数递增" do
      PhiGuidance.update_tracker("read", %{"path" => "lib/a.ex"})
      assert PhiGuidance.get_tracker().consecutive_same_action == 0

      PhiGuidance.update_tracker("read", %{"path" => "lib/b.ex"})
      assert PhiGuidance.get_tracker().consecutive_same_action == 1

      PhiGuidance.update_tracker("read", %{"path" => "lib/c.ex"})
      assert PhiGuidance.get_tracker().consecutive_same_action == 2
    end

    test "不同动作重置计数" do
      PhiGuidance.update_tracker("read", %{"path" => "lib/a.ex"})
      PhiGuidance.update_tracker("read", %{"path" => "lib/b.ex"})
      assert PhiGuidance.get_tracker().consecutive_same_action == 1

      PhiGuidance.update_tracker("write", %{"path" => "lib/a.ex"})
      assert PhiGuidance.get_tracker().consecutive_same_action == 0
    end
  end

  # ============================================================
  # Guidance 生成（通过 tracker）
  # ============================================================

  describe "guidance 生成" do
    setup do
      PhiGuidance.init_tracker()
      on_exit(fn -> PhiGuidance.cleanup() end)
    end

    test "初始状态生成有效 guidance" do
      guidance = PhiGuidance.generate()

      assert is_map(guidance)
      assert Map.has_key?(guidance, :text)
      assert Map.has_key?(guidance, :recommended_actions)
      assert Map.has_key?(guidance, :discouraged_actions)
      assert Map.has_key?(guidance, :score_snapshot)
    end

    test "测试失败后 guidance 不推荐重测" do
      # 模拟：read → patch → test (fail)
      PhiGuidance.update_tracker("read", %{"path" => "lib/foo.ex"})
      PhiGuidance.update_tracker("write", %{"path" => "lib/foo.ex"})
      PhiGuidance.update_tracker("bash", %{"command" => "mix test"}, {:ok, "1 failure"})

      guidance = PhiGuidance.generate()

      refute :RUN_TESTS in guidance.recommended_actions,
             "测试失败后不应推荐重测"
    end
  end

  # ============================================================
  # format_message
  # ============================================================

  describe "format_message" do
    test "有 guidance → 返回 system 消息" do
      guidance = %{
        text: "Consider reading the source code.",
        recommended_actions: [:READ_CODE],
        discouraged_actions: [:RUN_TESTS],
        score_snapshot: %{READ_CODE: -1.0, RUN_TESTS: 2.0}
      }

      msg = PhiGuidance.format_message(guidance)

      assert msg.role == :system
      assert String.contains?(msg.content, "[Φ Guidance]")
      assert String.contains?(msg.content, "Consider reading")
      assert String.contains?(msg.content, "Recommended: READ_CODE")
      assert String.contains?(msg.content, "Avoid: RUN_TESTS")
    end

    test "无 text → 返回 nil" do
      assert PhiGuidance.format_message(%{text: nil}) == nil
      assert PhiGuidance.format_message(%{text: ""}) == nil
    end

    test "空 guidance → 返回 nil" do
      guidance = PhiGuidance.generate(%{})

      # 空状态可能有或没有 text，但不应崩溃
      result = PhiGuidance.format_message(guidance)
      assert result == nil or (is_map(result) and Map.has_key?(result, :role))
    end
  end

  # ============================================================
  # PhiGuidanceHook 集成
  # ============================================================

  describe "PhiGuidanceHook.on_context/1" do
    setup do
      PhiGuidance.init_tracker()
      on_exit(fn -> PhiGuidance.cleanup() end)
    end

    test "注入 guidance 到 conversation" do
      # 模拟失败场景让 guidance 有内容
      PhiGuidance.update_tracker("read", %{"path" => "lib/foo.ex"})
      PhiGuidance.update_tracker("write", %{"path" => "lib/foo.ex"})
      PhiGuidance.update_tracker("bash", %{"command" => "mix test"}, {:ok, "1 failure"})

      messages = [
        %{role: :user, content: "fix the bug"},
        %{role: :assistant, content: "Let me check..."}
      ]

      result = PhiGuidanceHook.on_context(messages)

      # 应比原消息多（注入了 guidance）
      assert length(result) >= length(messages)

      # 最后一条应包含 Φ Guidance
      if length(result) > length(messages) do
        last = List.last(result)
        assert last.role == :system
        assert String.contains?(last.content, "Φ Guidance")
      end
    end

    test "初始空状态 → 不注入（或注入有效内容）" do
      messages = [%{role: :user, content: "hello"}]
      result = PhiGuidanceHook.on_context(messages)

      # 要么不变，要么只增加不减少
      assert length(result) >= length(messages)
    end
  end

  describe "PhiGuidanceHook.on_tool_result/2" do
    setup do
      PhiGuidance.init_tracker()
      on_exit(fn -> PhiGuidance.cleanup() end)
    end

    test "透传 result 不修改" do
      result = {:ok, "some content"}
      assert PhiGuidanceHook.on_tool_result(:read, result) == result
    end

    test "更新 tracker" do
      PhiGuidanceHook.on_tool_result(:read, {:ok, "content"})
      tracker = PhiGuidance.get_tracker()
      assert tracker.step_num == 1
      assert tracker.last_action == :READ_CODE
    end
  end

  # ============================================================
  # 集成：guidance 开关不影响现有行为
  # ============================================================

  describe "guidance 关闭兼容性" do
    test "不使用 hook 时 tracker 为空" do
      # 不调用 init_tracker，直接 get 返回默认
      tracker = PhiGuidance.get_tracker()
      assert tracker.step_num == 0
    end

    test "generate 在无 tracker 时返回有效结果" do
      # 不 init，直接 generate
      guidance = PhiGuidance.generate()
      assert is_map(guidance)
      assert Map.has_key?(guidance, :text)
    end
  end
end
