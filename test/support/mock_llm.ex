defmodule Gong.MockLLM do
  @moduledoc """
  Mock LLM 测试基础设施。

  通过策略层直接驱动 ReAct 循环，绕过真实 LLM/HTTP 调用。
  每次 LLM 调用点从预定义响应队列中弹出下一个响应。
  """

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.ReAct
  alias Jido.AI.Directive
  alias Jido.Instruction

  @doc """
  初始化 agent（策略层），返回初始化后的 agent 结构体。
  """
  @spec init_agent() :: struct()
  def init_agent do
    # Gong.Agent.new() 内部已调用 ReAct.init/2 并传入正确的 strategy_opts
    # 不需要再次调用 ReAct.init
    Gong.Agent.new()
  end

  @doc """
  驱动完整的 ReAct 对话循环（策略层）。

  给定用户 prompt 和 mock 响应队列，自动执行：
  1. 发送 start 指令 → 获取 LLM call_id
  2. 注入 mock LLM 响应
  3. 如果是 tool_calls → 执行真实工具 → 发送 tool_result → 循环
  4. 如果是 final_answer → 返回结果

  响应队列格式：
  - `{:text, "内容"}` — final_answer
  - `{:tool_calls, [%{name: "...", arguments: %{}}]}` — 工具调用
  - `{:error, "错误信息"}` — LLM 错误

  第 4 个参数 hooks 为 Hook 模块列表，默认为空。

  返回 `{:ok, reply, agent}` 或 `{:error, reason, agent}`
  """
  @spec run_chat(struct(), String.t(), [tuple()], [module()]) ::
          {:ok, String.t(), struct()} | {:error, term(), struct()}
  def run_chat(agent, prompt, response_queue, hooks \\ [], opts \\ []) do
    # 发送 telemetry: agent 开始
    :telemetry.execute([:gong, :agent, :start], %{count: 1}, %{prompt: prompt})

    # Hook: on_input — 变换或短路用户输入
    case Gong.HookRunner.pipe_input(hooks, prompt, []) do
      :handled ->
        # 输入被 hook 完全处理，不进入 Agent 循环
        :telemetry.execute([:gong, :agent, :end], %{count: 1}, %{prompt: prompt})
        {:ok, "", agent}

      {:transform, new_prompt, _images} ->
        do_run_chat(agent, new_prompt, response_queue, hooks, opts)

      :passthrough ->
        do_run_chat(agent, prompt, response_queue, hooks, opts)
    end
  end

  defp do_run_chat(agent, prompt, response_queue, hooks, opts) do
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

    # 从 directives 中提取 call_id
    call_id = extract_call_id(directives)

    # 驱动 ReAct 循环
    result = drive_loop(agent, call_id, response_queue, hooks, opts)

    # 发送 telemetry: agent 结束
    :telemetry.execute([:gong, :agent, :end], %{count: 1}, %{prompt: prompt})

    result
  end

  # ── 内部循环驱动 ──

  defp drive_loop(agent, call_id, [response | rest], hooks, opts) do
    # ── Auto-retry：transient 错误自动重试 ──
    case response do
      {:error, error_msg} ->
        error_class = Gong.Retry.classify_error(error_msg)
        attempt = Keyword.get(opts, :retry_attempt, 0)

        if Gong.Retry.should_retry?(error_class, attempt) do
          # 可重试：发送 retry telemetry，跳过当前错误，用下一个响应
          :telemetry.execute([:gong, :retry], %{attempt: attempt + 1}, %{
            error_class: error_class, error: error_msg
          })
          new_opts = Keyword.put(opts, :retry_attempt, attempt + 1)
          drive_loop(agent, call_id, rest, hooks, new_opts)
        else
          # 不可重试：走正常流程
          drive_loop_process(agent, call_id, response, rest, hooks, opts)
        end

      _ ->
        # 成功响应：重置重试计数，走正常流程
        opts = Keyword.put(opts, :retry_attempt, 0)
        drive_loop_process(agent, call_id, response, rest, hooks, opts)
    end
  end

  defp drive_loop(agent, _call_id, [], _hooks, _opts) do
    state = StratState.get(agent, %{})

    case state[:status] do
      :completed -> {:ok, state[:result] || "", agent}
      :error -> {:error, state[:result] || "unknown error", agent}
      _ -> {:error, "response queue exhausted while status=#{state[:status]}", agent}
    end
  end

  # 响应处理的核心逻辑（从 drive_loop 中提取）
  defp drive_loop_process(agent, call_id, response, rest, hooks, opts) do
    # 发送 telemetry: turn 开始
    :telemetry.execute([:gong, :turn, :start], %{count: 1}, %{})

    # Hook: on_context — 变换上下文消息
    # 提取当前 conversation，让 hook 有机会注入/修改
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

    # 构建 LLM 结果
    llm_params = build_llm_result(call_id, response)

    result_instruction = %Instruction{
      action: ReAct.llm_result_action(),
      params: llm_params
    }

    {agent, directives} = ReAct.cmd(agent, [result_instruction], %{})

    # 检查策略状态
    state = StratState.get(agent, %{})

    result =
      case state[:status] do
        :completed ->
          {:ok, state[:result] || "", agent}

        :error ->
          {:error, state[:result] || "unknown error", agent}

        :awaiting_tool ->
          # 提取 tool_calls 用于 telemetry
          pending = state[:pending_tool_calls] || []
          tool_names = Enum.map(pending, & &1.name)

          # 发送 telemetry: turn 结束（含 tool_calls）
          :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: tool_names})

          # 执行工具调用（带 hook + steering）
          {agent, new_call_id} = execute_pending_tools(agent, state, directives, hooks, opts)

          # 继续循环
          drive_loop(agent, new_call_id, rest, hooks, opts)

        :awaiting_llm ->
          # 发送 telemetry: turn 结束
          :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})

          # 需要下一次 LLM 调用
          new_call_id = extract_call_id(directives) || call_id
          drive_loop(agent, new_call_id, rest, hooks, opts)

        other ->
          {:error, "unexpected status: #{other}", agent}
      end

    # 非递归返回时发送 turn end
    case result do
      {:ok, _, _} ->
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})

      {:error, _, _} ->
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})

      _ ->
        :ok
    end

    result
  end

  # ── 工具执行（带 Hook + Steering 集成）──

  defp execute_pending_tools(agent, state, _directives, hooks, opts) do
    pending = state[:pending_tool_calls] || []
    config = state[:config] || %{}
    actions_by_name = config[:actions_by_name] || %{}

    # 合并工具上下文
    base_ctx = config[:base_tool_context] || %{}
    run_ctx = state[:run_tool_context] || %{}
    tool_context = Map.merge(base_ctx, run_ctx)

    # Steering 配置：after_tool 表示执行 N 个工具后注入 steering 跳过剩余
    steering_config = Keyword.get(opts, :steering_config)

    # 执行每个待处理的工具调用（带 steering 中断检查）
    {agent, _tool_idx} =
      pending
      |> Enum.with_index()
      |> Enum.reduce({agent, 0}, fn {tc, tool_idx}, {acc_agent, _} ->
        tool_name = tc.name
        arguments = tc.arguments || %{}
        tool_atom = to_atom_safe(tool_name)

        # Steering 中断：已执行 after_tool 个工具后，跳过剩余
        if steering_config && tool_idx >= steering_config.after_tool do
          result = Gong.Steering.skip_result(tool_name)

          # 发送 telemetry: 跳过的 tool
          :telemetry.execute([:gong, :tool, :start], %{count: 1}, %{
            tool: tool_name, arguments: arguments
          })
          :telemetry.execute([:gong, :tool, :stop], %{count: 1}, %{
            tool: tool_name, result: result
          })

          # 发送 skip result 给 ReAct 策略
          tool_result_instruction = %Instruction{
            action: ReAct.tool_result_action(),
            params: %{call_id: tc.id, tool_name: tool_name, result: result}
          }

          {new_agent, _directives} = ReAct.cmd(acc_agent, [tool_result_instruction], %{})
          {new_agent, tool_idx}
        else
          # 正常执行工具

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
                # 查找 action 模块并执行
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
          {new_agent, tool_idx}
        end
      end)

    # 获取新的 call_id（如果有新的 LLM 调用）
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

  defp build_llm_result(call_id, {:text, text}) do
    %{
      call_id: call_id,
      result: {:ok, %{type: :final_answer, text: text, tool_calls: []}}
    }
  end

  defp build_llm_result(call_id, {:tool_calls, tool_calls}) do
    formatted =
      Enum.with_index(tool_calls, fn tc, idx ->
        %{
          id: Map.get(tc, :id, "tool_call_#{idx}"),
          name: tc.name,
          arguments: tc.arguments
        }
      end)

    %{
      call_id: call_id,
      result: {:ok, %{type: :tool_calls, text: "", tool_calls: formatted}}
    }
  end

  defp build_llm_result(call_id, {:error, error_msg}) do
    %{
      call_id: call_id,
      result: {:error, error_msg}
    }
  end

  defp to_atom_safe(key) when is_atom(key), do: key
  defp to_atom_safe(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      _ -> String.to_atom(key)
    end
  end

  # ── Conversation 更新辅助 ──

  defp update_conversation(agent, new_conversation) do
    # 更新 agent 策略状态中的 conversation
    strategy = Map.get(agent.state, :__strategy__, %{})
    updated_strategy = Map.put(strategy, :conversation, new_conversation)
    updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
    %{agent | state: updated_state}
  end

  # ── AgentServer 辅助（用于 E2E 测试）──

  @doc "获取 agent 策略状态（从 AgentServer）"
  @spec get_strategy_state(pid()) :: map()
  def get_strategy_state(pid) do
    {:ok, server_state} = Jido.AgentServer.state(pid)
    Map.get(server_state.agent.state, :__strategy__, %{})
  end

  @doc "从策略状态提取工具调用记录"
  @spec extract_tool_calls(map()) :: [map()]
  def extract_tool_calls(strategy_state) do
    conversation = Map.get(strategy_state, :conversation, [])

    conversation
    |> Enum.flat_map(fn
      %{role: :assistant, tool_calls: tcs} when is_list(tcs) ->
        Enum.map(tcs, fn tc ->
          %{name: tc[:name] || tc["name"], arguments: tc[:arguments] || tc["arguments"] || %{}}
        end)
      _ -> []
    end)
  end
end
