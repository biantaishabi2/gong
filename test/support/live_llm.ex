defmodule Gong.LiveLLM do
  @moduledoc """
  真实 LLM + Hook 集成的 Agent 循环。

  复用 MockLLM 的 hook/tool 执行逻辑，但将"从队列弹出响应"
  替换为真实的 DeepSeek API 调用（通过 ReqLLM）。
  这样在同一条代码路径上可以同时测试 Hook 和真实 LLM。
  """

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.ReAct
  alias Jido.AI.Directive
  alias Jido.Instruction

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
    # 发送 telemetry: agent 开始
    :telemetry.execute([:gong, :agent, :start], %{count: 1}, %{prompt: prompt})

    # Hook: on_input — 变换或短路用户输入
    case Gong.HookRunner.pipe_input(hooks, prompt, []) do
      :handled ->
        :telemetry.execute([:gong, :agent, :end], %{count: 1}, %{prompt: prompt})
        {:ok, "", agent}

      {:transform, new_prompt, _images} ->
        do_run_chat(agent, new_prompt, hooks, opts)

      :passthrough ->
        do_run_chat(agent, prompt, hooks, opts)
    end
  end

  defp do_run_chat(agent, prompt, hooks, opts) do
    # Hook: on_before_agent — Agent 调用前注入/变换
    {prompt, _system, extra_messages} =
      Gong.HookRunner.pipe_before_agent(hooks, prompt, "")

    # 将 hook 注入的 extra messages 写入 conversation
    agent =
      if extra_messages != [] do
        :telemetry.execute([:gong, :hook, :on_before_agent, :applied], %{count: 1}, %{
          extra_count: length(extra_messages)
        })
        strategy = Map.get(agent.state, :__strategy__, %{})
        conversation = Map.get(strategy, :conversation, [])
        updated_strategy = Map.put(strategy, :conversation, extra_messages ++ conversation)
        updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
        %{agent | state: updated_state}
      else
        agent
      end

    # 发送 start 指令
    start_instruction = %Instruction{
      action: ReAct.start_action(),
      params: %{query: prompt}
    }

    {agent, directives} = ReAct.cmd(agent, [start_instruction], %{})
    call_id = extract_call_id(directives)

    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    # 驱动 ReAct 循环（真实 LLM）
    result = drive_loop_live(agent, call_id, hooks, opts, 0, max_iter)

    # 发送 telemetry: agent 结束
    :telemetry.execute([:gong, :agent, :end], %{count: 1}, %{prompt: prompt})

    result
  end

  # ── 真实 LLM 循环驱动 ──

  defp drive_loop_live(agent, _call_id, _hooks, _opts, iteration, max_iter)
       when iteration >= max_iter do
    {:error, "达到最大迭代次数 #{max_iter}", agent}
  end

  defp drive_loop_live(agent, call_id, hooks, opts, iteration, max_iter) do
    # 发送 telemetry: turn 开始
    :telemetry.execute([:gong, :turn, :start], %{count: 1}, %{})

    # Hook: on_context — 变换上下文消息
    strategy_state = StratState.get(agent, %{})
    conversation = Map.get(strategy_state, :conversation, [])
    new_conversation = Gong.HookRunner.pipe(hooks, :on_context, conversation, [])

    # 如果 hook 修改了 conversation，更新到 agent state 中
    agent =
      if new_conversation != conversation do
        :telemetry.execute([:gong, :hook, :on_context, :applied], %{count: 1}, %{
          added_count: length(new_conversation) - length(conversation)
        })
        update_conversation(agent, new_conversation)
      else
        agent
      end

    # 调用真实 LLM API
    case call_real_llm(agent) do
      {:ok, llm_response} ->
        # 将 LLM 响应注入 ReAct 策略
        llm_params = build_llm_result_from_response(call_id, llm_response)

        result_instruction = %Instruction{
          action: ReAct.llm_result_action(),
          params: llm_params
        }

        {agent, directives} = ReAct.cmd(agent, [result_instruction], %{})
        state = StratState.get(agent, %{})

        case state[:status] do
          :completed ->
            :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
            {:ok, state[:result] || "", agent}

          :error ->
            :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
            {:error, state[:result] || "unknown error", agent}

          :awaiting_tool ->
            pending = state[:pending_tool_calls] || []
            tool_names = Enum.map(pending, & &1.name)
            :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: tool_names})

            # 执行工具调用（带 hook 集成）
            {agent, new_call_id} = execute_pending_tools(agent, state, directives, hooks)
            drive_loop_live(agent, new_call_id, hooks, opts, iteration + 1, max_iter)

          :awaiting_llm ->
            :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
            new_call_id = extract_call_id(directives) || call_id
            drive_loop_live(agent, new_call_id, hooks, opts, iteration + 1, max_iter)

          other ->
            :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
            {:error, "unexpected status: #{other}", agent}
        end

      {:error, reason} ->
        # LLM 调用失败，注入错误
        llm_params = %{
          call_id: call_id,
          result: {:error, to_string(reason)}
        }

        result_instruction = %Instruction{
          action: ReAct.llm_result_action(),
          params: llm_params
        }

        {agent, _directives} = ReAct.cmd(agent, [result_instruction], %{})
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        {:error, "LLM 调用失败: #{inspect(reason)}", agent}
    end
  end

  # ── 真实 LLM 调用 ──

  defp call_real_llm(agent) do
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    model = config[:model] || "deepseek:deepseek-chat"
    reqllm_tools = config[:reqllm_tools] || []
    conversation = Map.get(state, :conversation, [])

    # 将内部 conversation 格式转换为 ReqLLM Context 格式
    messages = convert_conversation(conversation)

    # 构建选项
    opts = [tools: reqllm_tools, receive_timeout: @llm_timeout]

    case ReqLLM.generate_text(model, messages, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # 将策略内部的 conversation 消息转为 ReqLLM 接受的格式
  defp convert_conversation(conversation) do
    Enum.map(conversation, fn msg ->
      role = to_string(Map.get(msg, :role, "user"))

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
        if tool_call_id = Map.get(msg, :tool_call_id) do
          Map.put(base, :tool_call_id, tool_call_id)
        else
          base
        end

      base
    end)
  end

  # ── 从 ReqLLM Response 构建 ReAct llm_result ──

  defp build_llm_result_from_response(call_id, response) do
    tool_calls = ReqLLM.Response.tool_calls(response)
    text = ReqLLM.Response.text(response)

    if tool_calls != [] do
      # 工具调用响应
      formatted =
        Enum.map(tool_calls, fn tc ->
          tc_map = ReqLLM.ToolCall.from_map(tc)
          %{
            id: tc_map.id,
            name: tc_map.name,
            arguments: tc_map.arguments
          }
        end)

      %{
        call_id: call_id,
        result: {:ok, %{type: :tool_calls, text: text || "", tool_calls: formatted}}
      }
    else
      # 纯文本响应
      %{
        call_id: call_id,
        result: {:ok, %{type: :final_answer, text: text || "", tool_calls: []}}
      }
    end
  end

  # ── 工具执行（带 Hook 集成）— 复用 MockLLM 的逻辑 ──

  defp execute_pending_tools(agent, state, _directives, hooks) do
    pending = state[:pending_tool_calls] || []
    config = state[:config] || %{}
    actions_by_name = config[:actions_by_name] || %{}

    # 合并工具上下文
    base_ctx = config[:base_tool_context] || %{}
    run_ctx = state[:run_tool_context] || %{}
    tool_context = Map.merge(base_ctx, run_ctx)

    # 执行每个待处理的工具调用
    agent =
      Enum.reduce(pending, agent, fn tc, acc_agent ->
        tool_name = tc.name
        arguments = tc.arguments || %{}
        tool_atom = to_atom_safe(tool_name)

        # 发送 telemetry: tool 开始
        :telemetry.execute([:gong, :tool, :start], %{count: 1}, %{
          tool: tool_name,
          arguments: arguments
        })

        # Gate: before_tool_call
        gate_result = Gong.HookRunner.gate(hooks, :before_tool_call, [tool_atom, arguments])

        result =
          case gate_result do
            :ok ->
              action_module = Map.get(actions_by_name, tool_name)

              raw_result =
                if action_module do
                  atom_args =
                    arguments
                    |> Enum.map(fn {k, v} -> {to_atom_safe(k), v} end)
                    |> Map.new()

                  try do
                    case action_module.run(atom_args, tool_context) do
                      {:ok, data} -> {:ok, data}
                      {:error, reason} -> {:error, to_string(reason)}
                    end
                  rescue
                    e -> {:error, Exception.message(e)}
                  end
                else
                  {:error, "Unknown tool: #{tool_name}"}
                end

              # Pipe: on_tool_result 变换结果
              Gong.HookRunner.pipe(hooks, :on_tool_result, raw_result, [tool_atom])

            {:blocked, reason} ->
              {:error, "Blocked by hook: #{reason}"}
          end

        # 发送 telemetry: tool 结束
        :telemetry.execute([:gong, :tool, :stop], %{count: 1}, %{
          tool: tool_name,
          result: result
        })

        # 发送 tool_result
        tool_result_instruction = %Instruction{
          action: ReAct.tool_result_action(),
          params: %{
            call_id: tc.id,
            tool_name: tool_name,
            result: result
          }
        }

        {new_agent, _directives} = ReAct.cmd(acc_agent, [tool_result_instruction], %{})
        new_agent
      end)

    # 获取新的 call_id
    new_state = StratState.get(agent, %{})
    new_call_id = new_state[:current_llm_call_id]

    {agent, new_call_id}
  end

  # ── 辅助函数 ──

  defp extract_call_id(directives) do
    Enum.find_value(directives, fn
      %Directive.LLMStream{id: id} -> id
      _ -> nil
    end)
  end

  defp update_conversation(agent, new_conversation) do
    strategy = Map.get(agent.state, :__strategy__, %{})
    updated_strategy = Map.put(strategy, :conversation, new_conversation)
    updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
    %{agent | state: updated_state}
  end

  defp to_atom_safe(key) when is_atom(key), do: key
  defp to_atom_safe(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      _ -> String.to_atom(key)
    end
  end
end
