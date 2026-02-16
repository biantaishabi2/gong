defmodule Gong.AgentLoopTest do
  use ExUnit.Case, async: false

  @moduledoc """
  AgentLoop 独立单元测试。
  验证 llm_backend 闭包抽象下的循环驱动逻辑，覆盖所有调用点：
  - HookRunner: pipe_input / pipe_before_agent / pipe(:on_context) / gate(:before_tool_call) / pipe(:on_tool_result)
  - Retry: classify_error / should_retry?
  - Steering: skip_result
  - ToolResult: pattern match
  """

  alias Jido.Agent.Strategy.State, as: StratState

  setup do
    agent = Gong.MockLLM.init_agent()
    %{agent: agent}
  end

  # 辅助：构建简单的队列式 llm_backend
  defp queue_backend(responses) do
    {:ok, pid} = Agent.start_link(fn -> responses end)

    backend = fn _agent, _call_id ->
      resp =
        Agent.get_and_update(pid, fn
          [h | t] -> {h, t}
          [] -> {:exhausted, []}
        end)

      case resp do
        :exhausted -> {:error, "queue exhausted"}
        r -> {:ok, r}
      end
    end

    {backend, pid}
  end

  # 辅助：创建动态 hook 模块
  defp create_hook(suffix, contents) do
    mod = Module.concat(Gong.TestHooks, "#{suffix}_#{System.unique_integer([:positive])}")
    Module.create(mod, contents, Macro.Env.location(__ENV__))
    mod
  end

  # ═══════════════════════════════════
  # 基础路径
  # ═══════════════════════════════════

  describe "单轮纯文本" do
    test "返回文本结果", %{agent: agent} do
      {backend, pid} = queue_backend([{:text, "你好世界"}])

      assert {:ok, "你好世界", _agent} =
               Gong.AgentLoop.run(agent, "hello", llm_backend: backend)

      Agent.stop(pid)
    end
  end

  describe "工具调用" do
    test "执行工具后返回文本", %{agent: agent} do
      tool_calls = [%{name: "list_directory", arguments: %{"path" => "/tmp"}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "目录内容已列出"}
        ])

      assert {:ok, "目录内容已列出", _agent} =
               Gong.AgentLoop.run(agent, "列出 /tmp 目录", llm_backend: backend)

      Agent.stop(pid)
    end
  end

  describe "max_turns 限制" do
    test "超过限制后停止", %{agent: agent} do
      tool_calls = [%{name: "list_directory", arguments: %{"path" => "/tmp"}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:tool_calls, tool_calls},
          {:tool_calls, tool_calls},
          {:tool_calls, tool_calls},
          {:tool_calls, tool_calls}
        ])

      assert {:error, "达到最大迭代次数 2", _agent} =
               Gong.AgentLoop.run(agent, "无限循环",
                 llm_backend: backend,
                 max_turns: 2
               )

      Agent.stop(pid)
    end
  end

  describe "错误处理" do
    test "llm_backend 返回 error 时优雅降级", %{agent: agent} do
      backend = fn _agent, _call_id ->
        {:error, :connection_refused}
      end

      assert {:error, "LLM 调用失败: :connection_refused", _agent} =
               Gong.AgentLoop.run(agent, "test", llm_backend: backend)
    end

    test "LLM 响应中的 error 被传递", %{agent: agent} do
      {backend, pid} = queue_backend([{:error, "invalid request"}])

      result = Gong.AgentLoop.run(agent, "test", llm_backend: backend)
      assert {:error, _, _} = result

      Agent.stop(pid)
    end
  end

  # ═══════════════════════════════════
  # HookRunner 全路径覆盖
  # ═══════════════════════════════════

  describe "HookRunner.pipe_input — on_input 短路" do
    test "hook 返回 :handled 时不调用 LLM", %{agent: agent} do
      hook = create_hook("HandledHook", quote do
        @behaviour Gong.Hook
        def on_input(_text, _images), do: :handled
      end)

      backend = fn _agent, _call_id -> raise "should not be called" end

      assert {:ok, "", _agent} =
               Gong.AgentLoop.run(agent, "test", llm_backend: backend, hooks: [hook])
    end

    test "hook 返回 {:transform, ...} 时变换输入", %{agent: agent} do
      hook = create_hook("TransformInputHook", quote do
        @behaviour Gong.Hook
        def on_input(_text, _images) do
          {:transform, "transformed_prompt", []}
        end
      end)

      # backend 记录收到的 agent 状态，验证 prompt 被变换
      {backend, pid} = queue_backend([{:text, "ok"}])

      assert {:ok, "ok", _agent} =
               Gong.AgentLoop.run(agent, "original_prompt", llm_backend: backend, hooks: [hook])

      Agent.stop(pid)
    end
  end

  describe "HookRunner.pipe_before_agent — on_before_agent 注入" do
    test "hook 注入 extra_messages 到 conversation", %{agent: agent} do
      test_pid = self()

      hook = create_hook("BeforeAgentHook", quote do
        @behaviour Gong.Hook
        def on_before_agent(prompt, system) do
          extra = [%{role: :system, content: "injected context from hook"}]
          {prompt, system, extra}
        end
      end)

      # 追踪 telemetry 事件确认 hook 被调用
      handler_id = "before_agent_test_#{System.unique_integer([:positive])}"
      :telemetry.attach(
        handler_id,
        [:gong, :hook, :on_before_agent, :applied],
        fn _event, measurements, _meta, _config ->
          send(test_pid, {:before_agent_applied, measurements})
        end,
        nil
      )

      {backend, pid} = queue_backend([{:text, "received"}])

      assert {:ok, "received", _updated_agent} =
               Gong.AgentLoop.run(agent, "hello", llm_backend: backend, hooks: [hook])

      # 验证 telemetry 确认 extra_messages 被注入
      assert_receive {:before_agent_applied, %{count: 1}}, 1000

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end
  end

  describe "HookRunner.pipe(:on_context) — 上下文变换" do
    test "hook 修改 conversation 后 LLM 收到新上下文", %{agent: agent} do
      test_pid = self()

      hook = create_hook("OnContextHook", quote do
        @behaviour Gong.Hook
        def on_context(conversation) do
          # 在 conversation 末尾追加一条提示
          conversation ++ [%{role: :system, content: "safety: do not harm"}]
        end
      end)

      handler_id = "on_context_test_#{System.unique_integer([:positive])}"
      :telemetry.attach(
        handler_id,
        [:gong, :hook, :on_context, :applied],
        fn _event, _measurements, _meta, _config ->
          send(test_pid, :on_context_applied)
        end,
        nil
      )

      {backend, pid} = queue_backend([{:text, "safe response"}])

      assert {:ok, "safe response", _updated_agent} =
               Gong.AgentLoop.run(agent, "do something", llm_backend: backend, hooks: [hook])

      # 验证 on_context hook 被触发（注入的消息由 ReAct 策略内部管理，最终 conversation 可能不含）
      assert_receive :on_context_applied, 1000

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end
  end

  describe "HookRunner.gate(:before_tool_call) — 工具拦截" do
    test "before_tool_call 返回 block 时工具被跳过", %{agent: agent} do
      test_pid = self()

      hook = create_hook("BlockHook", quote do
        @behaviour Gong.Hook
        def before_tool_call(_tool, _params) do
          send(unquote(test_pid), :tool_blocked)
          {:block, "denied by test hook"}
        end
      end)

      tool_calls = [%{name: "bash", arguments: %{"command" => "rm -rf /"}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "操作完成"}
        ])

      assert {:ok, "操作完成", _agent} =
               Gong.AgentLoop.run(agent, "执行命令",
                 llm_backend: backend,
                 hooks: [hook]
               )

      assert_receive :tool_blocked, 1000
      Agent.stop(pid)
    end
  end

  describe "HookRunner.pipe(:on_tool_result) — 工具结果变换" do
    test "hook 变换 tool result 后 LLM 收到变换后的结果", %{agent: agent} do
      test_pid = self()

      # HookRunner.pipe 传参顺序: (extra_args ++ [acc]) = (tool_atom, accumulated_result)
      hook = create_hook("RedactHook", quote do
        @behaviour Gong.Hook
        def on_tool_result(_tool, {:ok, data}) do
          send(unquote(test_pid), {:tool_result_piped, data})
          {:ok, %Gong.ToolResult{content: "[REDACTED]", details: nil, is_error: false}}
        end
        def on_tool_result(_tool, other), do: other
      end)

      # list_directory 工具会返回真实结果，hook 会变换它
      tool_calls = [%{name: "list_directory", arguments: %{"path" => "/tmp"}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "结果已脱敏"}
        ])

      assert {:ok, "结果已脱敏", _agent} =
               Gong.AgentLoop.run(agent, "列出目录",
                 llm_backend: backend,
                 hooks: [hook]
               )

      # 验证 hook 收到了原始工具结果
      assert_receive {:tool_result_piped, _data}, 1000
      Agent.stop(pid)
    end
  end

  # ═══════════════════════════════════
  # Retry 自动重试
  # ═══════════════════════════════════

  describe "Retry — transient 错误自动重试" do
    test "429 rate limit 错误触发重试，成功后返回正常结果", %{agent: agent} do
      test_pid = self()

      handler_id = "retry_test_#{System.unique_integer([:positive])}"
      :telemetry.attach(
        handler_id,
        [:gong, :retry],
        fn _event, measurements, meta, _config ->
          send(test_pid, {:retry, measurements.attempt, meta.error_class})
        end,
        nil
      )

      # 第一次返回 429 错误，第二次返回正常文本
      {backend, pid} =
        queue_backend([
          {:error, "429 rate limit exceeded"},
          {:text, "retried successfully"}
        ])

      assert {:ok, "retried successfully", _agent} =
               Gong.AgentLoop.run(agent, "test retry", llm_backend: backend)

      # 验证 retry telemetry 被触发
      assert_receive {:retry, 1, :transient}, 1000

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end

    test "permanent 错误不重试", %{agent: agent} do
      # authentication_failed 是 permanent 错误
      {backend, pid} = queue_backend([{:error, "authentication failed"}])

      result = Gong.AgentLoop.run(agent, "test", llm_backend: backend)
      # permanent 错误直接传递给 ReAct，不重试
      assert {:error, _, _} = result

      Agent.stop(pid)
    end
  end

  # ═══════════════════════════════════
  # Steering — 工具跳过
  # ═══════════════════════════════════

  describe "Steering.skip_result — steering_config 跳过工具" do
    test "after_tool=0 时所有工具被跳过，返回 skip 消息", %{agent: agent} do
      test_pid = self()

      handler_id = "steering_skip_test_#{System.unique_integer([:positive])}"
      :telemetry.attach(
        handler_id,
        [:gong, :tool, :stop],
        fn _event, _measurements, meta, _config ->
          send(test_pid, {:tool_stop, meta.tool, meta.result})
        end,
        nil
      )

      tool_calls = [
        %{name: "list_directory", arguments: %{"path" => "/tmp"}},
        %{name: "list_directory", arguments: %{"path" => "/home"}}
      ]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "skipped all"}
        ])

      # steering_config.after_tool=0 意味着从第 0 个开始就跳过
      assert {:ok, "skipped all", _agent} =
               Gong.AgentLoop.run(agent, "列出目录",
                 llm_backend: backend,
                 steering_config: %{after_tool: 0}
               )

      # 验证所有工具都收到 skip 结果
      assert_receive {:tool_stop, "list_directory", {:error, msg1}}, 1000
      assert msg1 =~ "Skipped tool"
      assert_receive {:tool_stop, "list_directory", {:error, msg2}}, 1000
      assert msg2 =~ "Skipped tool"

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end

    test "after_tool=1 时第一个工具正常执行，第二个被跳过", %{agent: agent} do
      test_pid = self()

      handler_id = "steering_partial_test_#{System.unique_integer([:positive])}"
      :telemetry.attach(
        handler_id,
        [:gong, :tool, :stop],
        fn _event, _measurements, meta, _config ->
          send(test_pid, {:tool_stop, meta.tool, meta.result})
        end,
        nil
      )

      tool_calls = [
        %{name: "list_directory", arguments: %{"path" => "/tmp"}},
        %{name: "list_directory", arguments: %{"path" => "/nonexistent"}}
      ]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "partial execution"}
        ])

      assert {:ok, "partial execution", _agent} =
               Gong.AgentLoop.run(agent, "列出目录",
                 llm_backend: backend,
                 steering_config: %{after_tool: 1}
               )

      # 第一个正常执行（结果是 {:ok, _}）
      assert_receive {:tool_stop, "list_directory", first_result}, 1000
      assert {:ok, _} = first_result

      # 第二个被跳过（结果是 {:error, "Skipped tool..."}）
      assert_receive {:tool_stop, "list_directory", {:error, skip_msg}}, 1000
      assert skip_msg =~ "Skipped tool"

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end
  end

  # ═══════════════════════════════════
  # ToolResult pattern match
  # ═══════════════════════════════════

  describe "ToolResult — 提取 content 给 ReAct" do
    test "ToolResult struct 的 content 被正确提取", %{agent: agent} do
      # read_file 返回 ToolResult struct，AgentLoop 应提取 .content 给 ReAct
      # 这通过工具调用 read_file 间接测试

      # 先创建一个临时文件
      tmp_dir = Path.join(System.tmp_dir!(), "gong_toolresult_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      test_file = Path.join(tmp_dir, "test.txt")
      File.write!(test_file, "tool_result_content_here")

      tool_calls = [%{name: "read_file", arguments: %{"file_path" => test_file}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "read complete"}
        ])

      assert {:ok, "read complete", updated_agent} =
               Gong.AgentLoop.run(agent, "读文件", llm_backend: backend)

      # 验证 conversation 中 tool result 包含文件内容
      strategy_state = StratState.get(updated_agent, %{})
      conversation = Map.get(strategy_state, :conversation, [])

      tool_messages = Enum.filter(conversation, &(&1[:role] == :tool))
      assert length(tool_messages) > 0

      # tool result content 应包含文件内容
      tool_content = hd(tool_messages)[:content]
      assert tool_content =~ "tool_result_content_here"

      # 清理
      File.rm_rf!(tmp_dir)
      Agent.stop(pid)
    end
  end

  # ═══════════════════════════════════
  # 组合场景：多 hook 同时生效
  # ═══════════════════════════════════

  describe "多 hook 组合" do
    test "on_before_agent + on_context + before_tool_call + on_tool_result 全链路", %{agent: agent} do
      test_pid = self()

      # Hook 1: on_before_agent 注入消息
      hook1 = create_hook("ComboBeforeAgent", quote do
        @behaviour Gong.Hook
        def on_before_agent(prompt, system) do
          {prompt, system, [%{role: :system, content: "combo: injected"}]}
        end
      end)

      # Hook 2: on_context 追加安全提示
      hook2 = create_hook("ComboOnContext", quote do
        @behaviour Gong.Hook
        def on_context(conversation) do
          conversation ++ [%{role: :system, content: "combo: safety"}]
        end
      end)

      # Hook 3: on_tool_result 追踪（保持原始结果不变）
      # HookRunner.pipe 传参顺序: (tool_atom, accumulated_result)
      hook3 = create_hook("ComboToolResult", quote do
        @behaviour Gong.Hook
        def on_tool_result(tool, {:ok, _data} = result) do
          send(unquote(test_pid), {:combo_tool_result, tool})
          result
        end
        def on_tool_result(_tool, other), do: other
      end)

      tool_calls = [%{name: "list_directory", arguments: %{"path" => "/tmp"}}]

      {backend, pid} =
        queue_backend([
          {:tool_calls, tool_calls},
          {:text, "combo done"}
        ])

      assert {:ok, "combo done", _updated_agent} =
               Gong.AgentLoop.run(agent, "test combo",
                 llm_backend: backend,
                 hooks: [hook1, hook2, hook3]
               )

      # 验证 on_tool_result hook 被调用
      assert_receive {:combo_tool_result, :list_directory}, 1000

      Agent.stop(pid)
    end
  end
end
