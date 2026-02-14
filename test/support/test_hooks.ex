defmodule Gong.TestHooks do
  @moduledoc "测试用 hook 模块集合"

  # ── 拦截型 ──

  defmodule AllowAll do
    @moduledoc "放行所有工具调用"
    @behaviour Gong.Hook
    def before_tool_call(_tool, _params), do: :ok
  end

  defmodule BlockBash do
    @moduledoc "阻止 bash 工具调用"
    @behaviour Gong.Hook
    def before_tool_call(:bash, _params), do: {:block, "需要确认"}
    def before_tool_call(_tool, _params), do: :ok
  end

  defmodule BlockAll do
    @moduledoc "阻止所有工具调用"
    @behaviour Gong.Hook
    def before_tool_call(_tool, _params), do: {:block, "全部禁止"}
  end

  defmodule CancelCompact do
    @moduledoc "取消 compaction 操作"
    @behaviour Gong.Hook
    def before_session_op(:compact, _meta), do: :cancel
    def before_session_op(_op, _meta), do: :ok
  end

  # ── 变换型：on_tool_result ──

  defmodule RedactApiKey do
    @moduledoc "脱敏工具结果中的 API Key"
    @behaviour Gong.Hook
    def on_tool_result(_tool, result) do
      case result do
        {:ok, data} when is_map(data) ->
          {:ok, Map.update(data, :content, "", fn c ->
            if is_binary(c) do
              String.replace(c, ~r/[A-Za-z0-9_-]{20,}/, "[REDACTED]")
            else
              c
            end
          end)}

        other ->
          other
      end
    end
  end

  defmodule AppendTag do
    @moduledoc "在工具结果后追加标签（用于串联测试）"
    @behaviour Gong.Hook

    # 动态生成带特定 tag 的模块
    def new(tag) do
      module_name = Module.concat(__MODULE__, "Tag_#{tag}")

      unless Code.ensure_loaded?(module_name) do
        contents =
          quote do
            @behaviour Gong.Hook
            def on_tool_result(_tool, result) do
              case result do
                {:ok, data} when is_map(data) ->
                  {:ok, Map.update(data, :content, unquote(tag), fn c ->
                    if is_binary(c), do: c <> unquote(tag), else: c
                  end)}

                other ->
                  other
              end
            end
          end

        Module.create(module_name, contents, Macro.Env.location(__ENV__))
      end

      module_name
    end
  end

  defmodule PartialModify do
    @moduledoc "只修改结果中的特定字段（部分修改测试）"
    @behaviour Gong.Hook
    def on_tool_result(_tool, result) do
      case result do
        {:ok, data} when is_map(data) ->
          {:ok, Map.put(data, :hook_modified, true)}

        other ->
          other
      end
    end
  end

  # ── 变换型：on_context ──

  defmodule InjectContext do
    @moduledoc "注入系统消息到上下文"
    @behaviour Gong.Hook
    def on_context(messages) do
      injected = %{role: :system, content: "[HOOK] 安全策略已加载"}
      [injected | messages]
    end
  end

  # ── 变换型：on_input ──

  defmodule TransformInput do
    @moduledoc "变换用户输入"
    @behaviour Gong.Hook
    def on_input(text, images) do
      {:transform, "[filtered] " <> text, images}
    end
  end

  defmodule HandleInput do
    @moduledoc "直接处理输入并短路（返回 :handled）"
    @behaviour Gong.Hook
    def on_input(_text, _images), do: :handled
  end

  # ── 变换型：on_before_agent ──

  defmodule InjectBeforeAgent do
    @moduledoc "Agent 调用前注入额外消息"
    @behaviour Gong.Hook
    def on_before_agent(prompt, system) do
      extra = [%{role: :system, content: "[HOOK] 注入的安全提示"}]
      {prompt, system, extra}
    end
  end

  # ── 特殊返回值测试 ──

  defmodule PassthroughInput do
    @moduledoc "on_input 返回 :passthrough 不做任何变换"
    @behaviour Gong.Hook
    def on_input(_text, _images), do: :passthrough
  end

  defmodule BadReturnGate do
    @moduledoc "gate 返回非预期值（测试 catch-all 处理）"
    @behaviour Gong.Hook
    def before_tool_call(_tool, _params), do: :unexpected_value
  end

  # ── 错误处理测试 ──

  defmodule CrashHook do
    @moduledoc "故意抛出异常的 hook"
    @behaviour Gong.Hook
    def before_tool_call(_tool, _params), do: raise("hook 崩溃了")
    def on_tool_result(_tool, _result), do: raise("hook 崩溃了")
  end

  defmodule SlowHook do
    @moduledoc "超时的 hook"
    @behaviour Gong.Hook
    def before_tool_call(_tool, _params) do
      Process.sleep(10_000)
      :ok
    end
  end

  # ── 深拷贝保护测试 ──

  defmodule MessageMutatorHook do
    @moduledoc "修改收到的 messages 以测试深拷贝保护"
    @behaviour Gong.Hook

    def on_context(messages) do
      # 尝试在原始消息上做修改
      Enum.map(messages, fn msg ->
        Map.put(msg, :mutated_by_hook, true)
      end)
    end
  end

  # ── 状态观察测试 ──

  defmodule StateObserverHook do
    @moduledoc "记录事件触发时的 state 快照"
    @behaviour Gong.Hook

    def on_context(messages) do
      # 记录观察到的消息到进程字典
      Process.put(:state_observer_snapshot, messages)
      messages
    end
  end

  # ── 异常传播测试 ──

  defmodule FailingEventHandler do
    @moduledoc "抛出异常以测试错误传播"
    @behaviour Gong.Hook

    def on_context(_messages) do
      raise "event handler failed deliberately"
    end
  end
end
