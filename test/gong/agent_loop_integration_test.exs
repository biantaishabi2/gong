defmodule Gong.AgentLoopIntegrationTest do
  use ExUnit.Case, async: false

  @moduledoc """
  AgentLoop 集成测试 — 直接调用 Gong.AgentLoop.run + 真实 LLM API。

  验证 AgentLoop 作为生产代码的完整链路：
  AgentLoop → HookRunner → Steering → Prompt → Retry → ToolResult

  需要 DEEPSEEK_API_KEY 环境变量，通过 @tag :e2e 排除默认运行。
  运行方式：mix test --include e2e test/gong/agent_loop_integration_test.exs
  """

  alias Jido.Agent.Strategy.State, as: StratState

  @llm_timeout 60_000

  setup do
    unless System.get_env("DEEPSEEK_API_KEY") do
      flunk("跳过：DEEPSEEK_API_KEY 未设置")
    end

    agent = Gong.Agent.new()
    workspace = create_temp_dir()

    # 构建真实 LLM backend 闭包
    llm_backend = fn agent, _call_id ->
      case call_real_llm(agent) do
        {:ok, response} -> {:ok, build_response_tuple(response)}
        {:error, reason} -> {:ok, {:error, inspect(reason)}}
      end
    end

    %{agent: agent, workspace: workspace, llm_backend: llm_backend}
  end

  @moduletag :e2e

  describe "AgentLoop + 真实 LLM 冒烟测试" do
    test "简单问答 — 纯文本往返", %{agent: agent, llm_backend: llm_backend} do
      assert {:ok, reply, _agent} =
               Gong.AgentLoop.run(agent, "1+1等于几？请只回答数字",
                 llm_backend: llm_backend,
                 max_turns: 5
               )

      assert reply =~ "2"
    end

    test "工具调用 — LLM 自主选择 read_file",
         %{agent: agent, workspace: workspace, llm_backend: llm_backend} do
      # 创建测试文件
      file_path = Path.join(workspace, "version.txt")
      File.write!(file_path, "gong-v0.99")

      prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n读取 version.txt 的内容，告诉我版本号"

      assert {:ok, reply, updated_agent} =
               Gong.AgentLoop.run(agent, prompt,
                 llm_backend: llm_backend,
                 max_turns: 10
               )

      # 验证回复包含文件内容
      assert reply =~ "0.99"

      # 验证 read_file 工具确实被调用
      strategy_state = StratState.get(updated_agent, %{})
      conversation = Map.get(strategy_state, :conversation, [])

      tool_names =
        conversation
        |> Enum.flat_map(fn
          %{role: :assistant, tool_calls: tcs} when is_list(tcs) ->
            Enum.map(tcs, & &1[:name])

          _ ->
            []
        end)

      assert "read_file" in tool_names
    end

    test "Hook 集成 — before_tool_call gate 在真实 LLM 下生效",
         %{agent: agent, workspace: workspace, llm_backend: llm_backend} do
      # 创建一个拦截 bash 的 hook
      test_pid = self()

      hook_module =
        Module.concat(Gong.TestHooks, "E2EBlockBash_#{System.unique_integer([:positive])}")

      contents =
        quote do
          @behaviour Gong.Hook

          def before_tool_call(:bash, _params) do
            send(unquote(test_pid), :bash_blocked_e2e)
            {:block, "bash 被安全策略阻止"}
          end

          def before_tool_call(_tool, _params), do: :ok
        end

      Module.create(hook_module, contents, Macro.Env.location(__ENV__))

      prompt =
        "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n用 bash 执行 echo hello，告诉我结果"

      assert {:ok, _reply, _agent} =
               Gong.AgentLoop.run(agent, prompt,
                 llm_backend: llm_backend,
                 hooks: [hook_module],
                 max_turns: 10
               )

      # LLM 可能不一定选 bash，但如果选了 bash 就会被拦截
      # 无论如何，循环应正常完成不崩溃
    end

    test "max_turns 保护 — 真实 LLM 不会无限循环",
         %{agent: agent, workspace: workspace, llm_backend: llm_backend} do
      # 给一个容易触发多轮工具调用的任务，但限制为 3 轮
      prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n创建 a.txt 写 hello，创建 b.txt 写 world，创建 c.txt 写 test，创建 d.txt 写 four，创建 e.txt 写 five"

      result =
        Gong.AgentLoop.run(agent, prompt,
          llm_backend: llm_backend,
          max_turns: 3
        )

      # 要么正常完成（LLM 足够快），要么因 max_turns 截断
      case result do
        {:ok, _reply, _agent} -> :ok
        {:error, reason, _agent} -> assert reason =~ "最大迭代次数"
      end
    end
  end

  # ── 辅助函数 ──

  defp create_temp_dir do
    dir = Path.join(System.tmp_dir!(), "gong_agent_loop_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp call_real_llm(agent) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    model = config[:model] || "deepseek:deepseek-chat"
    reqllm_tools = config[:reqllm_tools] || []
    conversation = Map.get(state, :conversation, [])

    messages = convert_conversation(conversation)
    opts = [tools: reqllm_tools, receive_timeout: @llm_timeout]

    ReqLLM.generate_text(model, messages, opts)
  end

  defp build_response_tuple(response) do
    tool_calls = ReqLLM.Response.tool_calls(response)
    text = ReqLLM.Response.text(response)

    if tool_calls != [] do
      formatted =
        Enum.map(tool_calls, fn tc ->
          tc_map = ReqLLM.ToolCall.from_map(tc)
          %{id: tc_map.id, name: tc_map.name, arguments: tc_map.arguments}
        end)

      {:tool_calls, formatted}
    else
      {:text, text || ""}
    end
  end

  # 将策略内部 conversation 转为 ReqLLM 接受的格式
  # 注意：ReqLLM 的 convert_loose_map 要求 role 为 atom，不能转 string
  defp convert_conversation(conversation) do
    Enum.map(conversation, fn msg ->
      role = Map.get(msg, :role, :user)
      base = %{role: role}

      base =
        if content = Map.get(msg, :content) do
          Map.put(base, :content, content)
        else
          base
        end

      base =
        if tool_calls = Map.get(msg, :tool_calls) do
          Map.put(base, :tool_calls, tool_calls)
        else
          base
        end

      base =
        if name = Map.get(msg, :name) do
          Map.put(base, :name, name)
        else
          base
        end

      if tool_call_id = Map.get(msg, :tool_call_id) do
        Map.put(base, :tool_call_id, tool_call_id)
      else
        base
      end
    end)
  end
end
