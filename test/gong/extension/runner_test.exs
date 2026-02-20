defmodule Gong.Extension.RunnerTest do
  use ExUnit.Case, async: true

  alias Gong.Extension.Runner

  # 非法 hook：不实现 Gong.Hook behaviour
  defmodule FakeHook do
    def before_tool_call(_tool, _params), do: :ok
  end

  # 包含合法 hook 的 Extension mock
  defmodule ExtWithValidHook do
    def hooks, do: [Gong.TestHooks.AllowAll]
  end

  # 包含非法 hook 的 Extension mock
  defmodule ExtWithInvalidHook do
    def hooks, do: [FakeHook]
  end

  # 混合合法与非法 hook
  defmodule ExtWithMixedHooks do
    def hooks, do: [Gong.TestHooks.AllowAll, FakeHook]
  end

  describe "collect_hooks/1" do
    test "保留实现了 Gong.Hook behaviour 的模块" do
      ext_states = [%{module: ExtWithValidHook, state: %{}}]
      hooks = Runner.collect_hooks(ext_states)
      assert hooks == [Gong.TestHooks.AllowAll]
    end

    test "过滤未实现 Gong.Hook behaviour 的模块" do
      ext_states = [%{module: ExtWithInvalidHook, state: %{}}]
      hooks = Runner.collect_hooks(ext_states)
      assert hooks == []
    end

    test "混合场景只保留合法 hook" do
      ext_states = [%{module: ExtWithMixedHooks, state: %{}}]
      hooks = Runner.collect_hooks(ext_states)
      assert hooks == [Gong.TestHooks.AllowAll]
    end

    test "空 ext_states 返回空列表" do
      assert Runner.collect_hooks([]) == []
    end
  end
end
