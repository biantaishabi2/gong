defmodule Gong.PhiGuidance do
  @moduledoc """
  Φ Prompt 引导适配层（#2844）。

  把 Gong AgentLoop 的运行时状态翻译成 PhiGuidance 需要的 agent_state，
  调用核心 Φ 引导逻辑，返回可注入 conversation 的 guidance。

  ## 使用方式

  作为 Hook 使用（推荐）：

      opts = [hooks: [Gong.PhiGuidanceHook]]
      Gong.AgentLoop.run(agent, prompt, opts)

  或手动调用：

      guidance = Gong.PhiGuidance.generate(tracker_state)

  ## 状态跟踪

  通过进程字典 `:gong_phi_tracker` 在 AgentLoop 的 tool 执行过程中
  累积 agent_state。每个 tool call 后更新 tracker。
  """

  @type tracker :: %{
          step_num: non_neg_integer(),
          last_action: atom() | nil,
          last_test_result: boolean() | nil,
          consecutive_same_action: non_neg_integer(),
          has_read_code: boolean(),
          has_read_tests: boolean(),
          patch_count: non_neg_integer(),
          test_count: non_neg_integer(),
          read_count: non_neg_integer(),
          last_patch_failed: boolean()
        }

  @doc """
  初始化 tracker（存入进程字典）。
  """
  @spec init_tracker() :: :ok
  def init_tracker do
    Process.put(:gong_phi_tracker, new_tracker())
    :ok
  end

  @doc """
  获取当前 tracker 状态。
  """
  @spec get_tracker() :: tracker()
  def get_tracker do
    Process.get(:gong_phi_tracker, new_tracker())
  end

  @doc """
  根据工具调用结果更新 tracker。

  tool_name 会被映射到 Φ action 枚举：
  - read/grep/find/ls → READ_CODE
  - read（路径含 test）→ READ_TESTS
  - write/edit → PATCH
  - bash（内容含 test/mix test）→ RUN_TESTS
  """
  @spec update_tracker(String.t(), map(), term()) :: :ok
  def update_tracker(tool_name, arguments \\ %{}, result \\ nil) do
    tracker = get_tracker()
    action = classify_action(tool_name, arguments)

    new_tracker =
      if action do
        update_state(tracker, action, result)
      else
        tracker
      end

    Process.put(:gong_phi_tracker, new_tracker)
    :ok
  end

  @doc """
  生成 guidance。如果 UniboVariationCenter.PhiGuidance 可用，
  调用核心模块；否则返回空 guidance。
  """
  @spec generate() :: map()
  def generate do
    generate(get_tracker())
  end

  @spec generate(tracker()) :: map()
  def generate(tracker) do
    if Code.ensure_loaded?(UniboVariationCenter.PhiGuidance) do
      UniboVariationCenter.PhiGuidance.generate(tracker)
    else
      # 降级：核心模块不可用时返回空 guidance
      %{
        text: nil,
        recommended_actions: [],
        discouraged_actions: [],
        score_snapshot: %{}
      }
    end
  end

  @doc """
  将 guidance 格式化为可注入 conversation 的消息。
  """
  @spec format_message(map()) :: map() | nil
  def format_message(%{text: nil}), do: nil
  def format_message(%{text: ""}), do: nil

  def format_message(%{text: text, recommended_actions: rec, discouraged_actions: disc}) do
    parts = ["[Φ Guidance] #{text}"]

    parts =
      if rec != [] do
        rec_str = Enum.map_join(rec, ", ", &Atom.to_string/1)
        parts ++ ["Recommended: #{rec_str}"]
      else
        parts
      end

    parts =
      if disc != [] do
        disc_str = Enum.map_join(disc, ", ", &Atom.to_string/1)
        parts ++ ["Avoid: #{disc_str}"]
      else
        parts
      end

    content = Enum.join(parts, "\n")
    %{role: :system, content: content}
  end

  def format_message(_), do: nil

  @doc """
  清理 tracker（进程退出前调用）。
  """
  @spec cleanup() :: :ok
  def cleanup do
    Process.delete(:gong_phi_tracker)
    :ok
  end

  # ── 内部 ──

  defp new_tracker do
    %{
      step_num: 0,
      last_action: nil,
      last_test_result: nil,
      consecutive_same_action: 0,
      has_read_code: false,
      has_read_tests: false,
      patch_count: 0,
      test_count: 0,
      read_count: 0,
      last_patch_failed: false
    }
  end

  # 从 tool_name + arguments 推断 Φ action
  defp classify_action(tool_name, arguments) do
    tool = String.downcase(to_string(tool_name))
    path = get_path(arguments)

    cond do
      tool in ["read", "grep", "find", "ls"] and is_test_path?(path) ->
        :READ_TESTS

      tool in ["read", "grep", "find", "ls"] ->
        :READ_CODE

      tool in ["write", "edit"] ->
        :PATCH

      tool == "bash" and is_test_command?(arguments) ->
        :RUN_TESTS

      tool == "bash" ->
        # bash 默认不映射（可能是任意命令）
        nil

      true ->
        nil
    end
  end

  defp get_path(arguments) when is_map(arguments) do
    Map.get(arguments, "path", Map.get(arguments, :path, ""))
  end

  defp get_path(_), do: ""

  defp is_test_path?(path) when is_binary(path) do
    String.contains?(path, "test") or
      String.contains?(path, "_test.") or
      String.contains?(path, "spec/")
  end

  defp is_test_path?(_), do: false

  defp is_test_command?(arguments) when is_map(arguments) do
    cmd = Map.get(arguments, "command", Map.get(arguments, :command, ""))

    is_binary(cmd) and
      (String.contains?(cmd, "mix test") or
         String.contains?(cmd, "cargo test") or
         String.contains?(cmd, "pytest") or
         String.contains?(cmd, "npm test") or
         String.contains?(cmd, "jest"))
  end

  defp is_test_command?(_), do: false

  defp update_state(tracker, action, result) do
    # 更新 consecutive_same_action
    consecutive =
      if action == tracker.last_action do
        tracker.consecutive_same_action + 1
      else
        0
      end

    # 测试结果判定
    test_result =
      case {action, result} do
        {:RUN_TESTS, {:ok, content}} when is_binary(content) ->
          # 简单启发式：检查输出中是否含有 failures/errors
          not (String.contains?(content, "failures") or String.contains?(content, "error"))

        {:RUN_TESTS, {:ok, %{content: content}}} when is_binary(content) ->
          not (String.contains?(content, "failures") or String.contains?(content, "error"))

        _ ->
          tracker.last_test_result
      end

    last_patch_failed =
      case {action, test_result} do
        {:RUN_TESTS, false} -> true
        {:PATCH, _} -> false
        _ -> tracker.last_patch_failed
      end

    %{
      step_num: tracker.step_num + 1,
      last_action: action,
      last_test_result: test_result,
      consecutive_same_action: consecutive,
      has_read_code: tracker.has_read_code or action == :READ_CODE,
      has_read_tests: tracker.has_read_tests or action == :READ_TESTS,
      patch_count: tracker.patch_count + if(action == :PATCH, do: 1, else: 0),
      test_count: tracker.test_count + if(action == :RUN_TESTS, do: 1, else: 0),
      read_count:
        tracker.read_count + if(action in [:READ_CODE, :READ_TESTS], do: 1, else: 0),
      last_patch_failed: last_patch_failed
    }
  end
end
