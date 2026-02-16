defmodule Gong.HookRunnerTest do
  use ExUnit.Case, async: false

  # pi-mono bugfix 回归: 非激活工具也触发 before_tool_call hook
  # Pi#31438fd: HookRunner.gate 不应检查 active_tools

  describe "gate/3 对非激活工具" do
    test "非激活工具也触发 before_tool_call hook" do
      # 初始化 readonly 预设（只含 read/grep/find/ls）
      Gong.ToolConfig.init(preset: :readonly)

      test_pid = self()

      # 动态创建追踪 hook
      module_name =
        Module.concat(Gong.TestHooks, "TrackingHook_#{System.unique_integer([:positive])}")

      contents =
        quote do
          @behaviour Gong.Hook
          def before_tool_call(tool, params) do
            send(unquote(test_pid), {:hook_invoked, :before_tool_call, tool, params})
            :ok
          end
        end

      Module.create(module_name, contents, Macro.Env.location(__ENV__))

      # bash 不在 readonly 预设中，但 hook 应该仍然被调用
      Gong.HookRunner.gate([module_name], :before_tool_call, [:bash, %{}])

      assert_receive {:hook_invoked, :before_tool_call, :bash, %{}}, 1000
    end
  end
end
