defmodule Gong.LiveLLM do
  @moduledoc """
  真实 LLM + Hook 集成的 Agent 循环。

  核心循环逻辑已提取到 Gong.AgentLoop，本模块仅提供真实 LLM 的 llm_backend 实现。
  """

  alias Jido.Agent.Strategy.State, as: StratState

  @max_iterations 25
  @llm_timeout 60_000

  @doc """
  驱动完整的 ReAct 对话循环（真实 LLM）。

  与 MockLLM.run_chat 接口一致，但不需要 response_queue。
  每次需要 LLM 响应时调用真实 API。

  返回 `{:ok, reply, agent}` 或 `{:error, reason, agent}`
  """
  @spec run_chat(struct(), String.t(), [module()], keyword()) ::
          {:ok, String.t(), struct()} | {:error, term(), struct()}
  def run_chat(agent, prompt, hooks \\ [], opts \\ []) do
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    llm_backend = fn agent, _call_id ->
      case call_real_llm(agent) do
        {:ok, llm_response} ->
          {:ok, build_response_tuple(llm_response)}

        {:error, reason} ->
          {:ok, {:error, to_string(reason)}}
      end
    end

    Gong.AgentLoop.run(agent, prompt, [
      {:llm_backend, llm_backend},
      {:hooks, hooks},
      {:max_turns, max_iter}
      | opts
    ])
  end

  # ── 真实 LLM 调用 ──

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

  # 将 ReqLLM Response 转为 AgentLoop 期望的 response tuple
  defp build_response_tuple(response) do
    tool_calls = ReqLLM.Response.tool_calls(response)
    text = ReqLLM.Response.text(response)

    if tool_calls != [] do
      formatted =
        Enum.map(tool_calls, fn tc ->
          tc_map = ReqLLM.ToolCall.from_map(tc)
          %{
            id: tc_map.id,
            name: tc_map.name,
            arguments: tc_map.arguments
          }
        end)

      {:tool_calls, formatted}
    else
      {:text, text || ""}
    end
  end

  # 将策略内部的 conversation 消息转为 ReqLLM 接受的格式
  # ReqLLM 的 convert_loose_map 要求 role 为 atom，不能转 string
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
