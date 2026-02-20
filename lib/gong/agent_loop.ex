defmodule Gong.AgentLoop do
  @moduledoc """
  Agent 循环核心引擎。

  将 ReAct 策略驱动、Hook 执行、工具调用、Steering 等逻辑统一封装，
  通过 `llm_backend` 闭包参数抽象 LLM 调用方式（mock 队列 / 真实 API）。

  MockLLM 和 LiveLLM 变为薄包装，只需提供各自的 llm_backend 实现。
  """

  alias Gong.Stream
  alias Gong.Stream.Event, as: StreamEvent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.ReAct
  alias Jido.AI.Directive
  alias Jido.Instruction

  @doc """
  驱动完整的 ReAct 对话循环。

  ## 参数
    - agent: 初始化后的 agent 结构体
    - prompt: 用户输入
    - opts:
      - :llm_backend — `fn agent, call_id -> {:ok, response} | {:error, reason}` 闭包，
        每次需要 LLM 响应时调用。response 格式同 MockLLM 的 {:text, _} | {:tool_calls, _} | {:error, _}
      - :hooks — Hook 模块列表，默认 []
      - :max_turns — 最大轮数，默认 25
      - :steering_config — Steering 配置（可选）

  ## 返回
    `{:ok, reply, agent}` | `{:error, reason, agent}`
  """
  @spec run(struct(), String.t(), keyword()) ::
          {:ok, String.t(), struct()} | {:error, term(), struct()}
  def run(agent, prompt, opts \\ []) do
    llm_backend = Keyword.fetch!(opts, :llm_backend)
    hooks = Keyword.get(opts, :hooks, [])

    # Extension 集成：加载并初始化
    {ext_states, all_hooks} =
      case Gong.ExtensionIntegration.setup(opts) do
        {:ok, %{ext_states: states, hooks: ext_hooks}} ->
          {states, hooks ++ ext_hooks}

        {:error, _reason} ->
          {[], hooks}
      end

    # 发送 telemetry: agent 开始
    :telemetry.execute([:gong, :agent, :start], %{count: 1}, %{prompt: prompt})

    # Hook: on_input — 变换或短路用户输入
    result =
      try do
        case Gong.HookRunner.pipe_input(all_hooks, prompt, []) do
          :handled ->
            {:ok, "", agent}

          {:transform, new_prompt, _images} ->
            do_run(agent, new_prompt, llm_backend, all_hooks, opts)

          :passthrough ->
            do_run(agent, prompt, llm_backend, all_hooks, opts)
        end
      after
        # Extension 清理
        if ext_states != [] do
          Gong.ExtensionIntegration.teardown(ext_states)
        end
      end

    # 发送 telemetry: agent 结束
    :telemetry.execute([:gong, :agent, :end], %{count: 1}, %{prompt: prompt})

    result
  end

  # ── 内部：初始化 ReAct 循环 ──

  defp do_run(agent, prompt, llm_backend, hooks, opts) do
    # Hook: on_before_agent — Agent 调用前注入/变换
    {prompt, _system, extra_messages} =
      Gong.HookRunner.pipe_before_agent(hooks, prompt, "")

    # 构建动态 system prompt 并注入 conversation 头部
    system_prompt = Gong.Prompt.full_system_prompt(opts)

    agent = inject_extra_messages(agent, [%{role: :system, content: system_prompt}])

    # 将 hook 注入的 extra messages 写入 conversation
    agent =
      if extra_messages != [] do
        :telemetry.execute([:gong, :hook, :on_before_agent, :applied], %{count: 1}, %{
          extra_count: length(extra_messages)
        })

        inject_extra_messages(agent, extra_messages)
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

    max_turns = Keyword.get(opts, :max_turns, 25)

    # 驱动 ReAct 循环
    drive_loop(agent, call_id, llm_backend, hooks, opts, 0, max_turns)
  end

  # ── 循环驱动 ──

  defp drive_loop(agent, _call_id, _llm_backend, _hooks, _opts, turn, max_turns)
       when turn >= max_turns do
    {:error, "达到最大迭代次数 #{max_turns}", agent}
  end

  defp drive_loop(agent, call_id, llm_backend, hooks, opts, turn, max_turns) do
    # 发送 telemetry: turn 开始
    :telemetry.execute([:gong, :turn, :start], %{count: 1}, %{})

    # Hook: on_context — 变换上下文消息
    strategy_state = StratState.get(agent, %{})
    conversation = Map.get(strategy_state, :conversation, [])
    new_conversation = Gong.HookRunner.pipe(hooks, :on_context, conversation, [])

    agent =
      if new_conversation != conversation do
        :telemetry.execute([:gong, :hook, :on_context, :applied], %{count: 1}, %{
          added_count: length(new_conversation) - length(conversation)
        })

        update_conversation(agent, new_conversation)
      else
        agent
      end

    # AutoCompaction：在 on_context 之后、LLM 调用之前
    agent = maybe_agent_compact(agent, opts)

    # 调用 LLM backend 获取响应
    case llm_backend.(agent, call_id) do
      {:ok, response} ->
        # Auto-retry：transient 错误自动重试
        case maybe_retry(response, agent, call_id, llm_backend, hooks, opts, turn, max_turns) do
          :no_retry ->
            process_response(agent, call_id, response, llm_backend, hooks, opts, turn, max_turns)

          retry_result ->
            retry_result
        end

      {:error, reason} ->
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        {:error, "LLM 调用失败: #{inspect(reason)}", agent}
    end
  end

  # 检查是否需要自动重试（仅对 {:error, _} 类型响应）
  # 注意：retry 不消耗 turn 计数，因为是重试同一轮而非新一轮。
  # 由 Retry.should_retry?/2 内部的 max_retries=3 兜底防止无限重试。
  defp maybe_retry({:error, error_msg}, agent, call_id, llm_backend, hooks, opts, turn, max_turns) do
    decision = Gong.Retry.is_retryable_error(error_msg)
    attempt = Keyword.get(opts, :retry_attempt, 0)

    if Gong.Retry.should_retry?(decision, attempt) do
      :telemetry.execute([:gong, :retry], %{attempt: attempt + 1}, %{
        error_class: decision.error_class,
        retry_source: decision.source,
        retry_reason: decision.reason,
        error: error_msg
      })

      new_opts = Keyword.put(opts, :retry_attempt, attempt + 1)
      drive_loop(agent, call_id, llm_backend, hooks, new_opts, turn, max_turns)
    else
      :no_retry
    end
  end

  defp maybe_retry(_response, _agent, _call_id, _llm_backend, _hooks, _opts, _turn, _max_turns) do
    # 非错误响应：重置重试计数，不需要重试
    :no_retry
  end

  # 处理 LLM 响应
  defp process_response(agent, call_id, response, llm_backend, hooks, opts, turn, max_turns) do
    # 成功响应重置重试计数
    opts = Keyword.put(opts, :retry_attempt, 0)

    # 构建 LLM 结果并注入 ReAct 策略
    llm_params = build_llm_result(call_id, response)

    result_instruction = %Instruction{
      action: ReAct.llm_result_action(),
      params: llm_params
    }

    {agent, directives} = ReAct.cmd(agent, [result_instruction], %{})
    state = StratState.get(agent, %{})

    case state[:status] do
      :completed ->
        reply = state[:result] || ""
        emit_stream_event(StreamEvent.new(:text_start))
        emit_stream_event(StreamEvent.new(:text_delta, content: reply))
        emit_stream_event(StreamEvent.new(:text_end))
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        {:ok, reply, agent}

      :error ->
        error_msg = state[:result] || "unknown error"
        emit_stream_event(StreamEvent.new(:error, content: error_msg))
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        {:error, error_msg, agent}

      :awaiting_tool ->
        pending = state[:pending_tool_calls] || []
        tool_names = Enum.map(pending, & &1.name)
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: tool_names})

        # 执行工具调用（带 hook + steering）
        {agent, new_call_id} = execute_pending_tools(agent, state, directives, hooks, opts)
        drive_loop(agent, new_call_id, llm_backend, hooks, opts, turn + 1, max_turns)

      :awaiting_llm ->
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        new_call_id = extract_call_id(directives) || call_id
        drive_loop(agent, new_call_id, llm_backend, hooks, opts, turn + 1, max_turns)

      other ->
        :telemetry.execute([:gong, :turn, :end], %{count: 1}, %{tool_calls: []})
        {:error, "unexpected status: #{other}", agent}
    end
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

    # Steering 配置
    steering_config = Keyword.get(opts, :steering_config)

    # 执行每个待处理的工具调用
    {agent, _tool_idx} =
      pending
      |> Enum.with_index()
      |> Enum.reduce({agent, 0}, fn {tc, tool_idx}, {acc_agent, _} ->
        tool_name = tc.name
        arguments = tc.arguments || %{}
        tool_atom = to_atom_safe(tool_name)

        # Steering 中断：已执行 after_tool 个工具后，跳过剩余
        if steering_config && tool_idx >= steering_config.after_tool do
          execute_skipped_tool(acc_agent, tc, tool_name, arguments, tool_idx)
        else
          execute_single_tool(
            acc_agent,
            tc,
            tool_name,
            arguments,
            tool_atom,
            actions_by_name,
            tool_context,
            hooks,
            tool_idx
          )
        end
      end)

    # 获取新的 call_id
    new_state = StratState.get(agent, %{})
    new_call_id = new_state[:current_llm_call_id]

    {agent, new_call_id}
  end

  # Steering 跳过工具
  defp execute_skipped_tool(agent, tc, tool_name, arguments, tool_idx) do
    result = Gong.Steering.skip_result(tool_name)

    :telemetry.execute([:gong, :tool, :start], %{count: 1}, %{
      tool: tool_name,
      arguments: arguments
    })

    :telemetry.execute([:gong, :tool, :stop], %{count: 1}, %{
      tool: tool_name,
      result: result
    })

    tool_result_instruction = %Instruction{
      action: ReAct.tool_result_action(),
      params: %{call_id: tc.id, tool_name: tool_name, result: result}
    }

    {new_agent, _directives} = ReAct.cmd(agent, [tool_result_instruction], %{})
    {new_agent, tool_idx}
  end

  # 正常执行单个工具
  defp execute_single_tool(
         agent,
         tc,
         tool_name,
         arguments,
         tool_atom,
         actions_by_name,
         tool_context,
         hooks,
         tool_idx
       ) do
    # 发送 telemetry + stream 事件: tool 开始
    :telemetry.execute([:gong, :tool, :start], %{count: 1}, %{
      tool: tool_name,
      arguments: arguments
    })
    emit_stream_event(StreamEvent.new(:tool_start, tool_name: tool_name, tool_args: arguments))

    # Gate: before_tool_call
    gate_result = Gong.HookRunner.gate(hooks, :before_tool_call, [tool_atom, arguments])

    result =
      case gate_result do
        :ok ->
          # 查找 action 模块并执行
          action_module =
            Map.get(actions_by_name, tool_name) ||
              Map.get(actions_by_name, String.downcase(tool_name))

          raw_result = run_action(action_module, tool_name, arguments, tool_context)

          # Pipe: on_tool_result 变换结果
          Gong.HookRunner.pipe(hooks, :on_tool_result, raw_result, [tool_atom])

        {:blocked, reason} ->
          {:error, "Blocked by hook: #{reason}"}
      end

    # 发送 telemetry + stream 事件: tool 结束
    :telemetry.execute([:gong, :tool, :stop], %{count: 1}, %{
      tool: tool_name,
      result: result
    })
    emit_stream_event(StreamEvent.new(:tool_end, tool_name: tool_name))

    # 发送 tool_result（从 ToolResult 提取 content 给 ReAct）
    result_for_react =
      case result do
        {:ok, %Gong.ToolResult{content: content}} -> {:ok, %{content: content}}
        other -> other
      end

    tool_result_instruction = %Instruction{
      action: ReAct.tool_result_action(),
      params: %{
        call_id: tc.id,
        tool_name: tool_name,
        result: result_for_react
      }
    }

    {new_agent, _directives} = ReAct.cmd(agent, [tool_result_instruction], %{})
    {new_agent, tool_idx}
  end

  # 执行 action 模块
  defp run_action(nil, tool_name, _arguments, _tool_context) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  defp run_action(action_module, _tool_name, arguments, tool_context) do
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
  end

  # ── AutoCompaction 集成 ──

  defp maybe_agent_compact(agent, opts) do
    case Keyword.get(opts, :auto_compaction) do
      nil ->
        agent

      compaction_opts ->
        strategy_state = StratState.get(agent, %{})
        conversation = Map.get(strategy_state, :conversation, [])

        case Gong.AutoCompaction.auto_compact(conversation, compaction_opts) do
          {:compacted, new_messages, _summary} ->
            update_conversation(agent, new_messages)

          {:no_action, _} ->
            agent

          {:skipped, _} ->
            agent
        end
    end
  end

  # ── 辅助函数 ──

  defp extract_call_id(directives) do
    Enum.find_value(directives, fn
      %Directive.LLMStream{id: id} -> id
      _ -> nil
    end)
  end

  @doc false
  def build_llm_result(call_id, {:text, text}) do
    %{
      call_id: call_id,
      result: {:ok, %{type: :final_answer, text: text, tool_calls: []}}
    }
  end

  def build_llm_result(call_id, {:tool_calls, tool_calls}) do
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

  def build_llm_result(call_id, {:error, error_msg}) do
    %{
      call_id: call_id,
      result: {:error, error_msg}
    }
  end

  defp inject_extra_messages(agent, extra_messages) do
    strategy = Map.get(agent.state, :__strategy__, %{})
    conversation = Map.get(strategy, :conversation, [])
    updated_strategy = Map.put(strategy, :conversation, extra_messages ++ conversation)
    updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
    %{agent | state: updated_state}
  end

  defp update_conversation(agent, new_conversation) do
    strategy = Map.get(agent.state, :__strategy__, %{})
    updated_strategy = Map.put(strategy, :conversation, new_conversation)
    updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
    %{agent | state: updated_state}
  end

  defp to_atom_safe(key) when is_atom(key), do: key

  defp to_atom_safe(key) when is_binary(key) do
    # 优先使用已存在的 atom，避免 atom 泄漏。
    # 工具名来自 LLM 响应，集合有限，fallback 到 to_atom 风险可控。
    try do
      String.to_existing_atom(key)
    rescue
      _ -> String.to_atom(key)
    end
  end

  # ── Session backend 适配器 ──

  @doc """
  Session backend 适配器 — 将 AgentLoop 包装为 Session 期望的 backend 闭包。

  model_config 包含 provider/model_id/api_key_env，用于构建 ReqLLM 调用。
  返回 `{:ok, reply}` 或 `{:error, reason}`，符合 Session.call_backend 期望的格式。
  """
  @bdd_instruction %{kind: :when, name: :run_as_backend, params: %{message: :string, model_str: :string}, returns: "{:ok, reply} | {:error, reason}"}
  @spec run_as_backend(String.t(), keyword(), map(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def run_as_backend(message, _opts, _context, model_config) do
    model_str = "#{model_config[:provider]}:#{model_config[:model_id]}"
    agent = Gong.Agent.new()

    llm_backend = fn agent, _call_id ->
      state = StratState.get(agent, %{})
      conversation = Map.get(state, :conversation, [])
      messages = format_conversation_for_reqllm(conversation)

      case ReqLLM.generate_text(model_str, messages, receive_timeout: 60_000) do
        {:ok, response} -> {:ok, parse_reqllm_response(response)}
        {:error, reason} -> {:ok, {:error, to_string(reason)}}
      end
    end

    case run(agent, message, llm_backend: llm_backend) do
      {:ok, reply, _agent} -> {:ok, reply}
      {:error, reason, _agent} -> {:error, reason}
    end
  end

  # 将 ReAct conversation 格式转为 ReqLLM 期望的 messages 格式
  defp format_conversation_for_reqllm(conversation) do
    Enum.map(conversation, fn msg ->
      base = %{role: Map.get(msg, :role, :user)}
      base = if c = Map.get(msg, :content), do: Map.put(base, :content, c), else: base
      base = if tc = Map.get(msg, :tool_calls), do: Map.put(base, :tool_calls, tc), else: base
      base = if n = Map.get(msg, :name), do: Map.put(base, :name, n), else: base
      if tid = Map.get(msg, :tool_call_id), do: Map.put(base, :tool_call_id, tid), else: base
    end)
  end

  # 解析 ReqLLM 响应为 AgentLoop 期望的 tuple 格式
  defp parse_reqllm_response(response) do
    tool_calls = ReqLLM.Response.tool_calls(response)

    if tool_calls != [] do
      formatted =
        Enum.map(tool_calls, fn tc ->
          tc_map = ReqLLM.ToolCall.from_map(tc)
          %{id: tc_map.id, name: tc_map.name, arguments: tc_map.arguments}
        end)
      {:tool_calls, formatted}
    else
      {:text, ReqLLM.Response.text(response) || ""}
    end
  end

  # ── Stream 事件发射 ──

  @doc """
  设置当前进程的 stream 事件回调。
  回调签名: `fn %Stream.Event{} -> :ok end`
  """
  @bdd_instruction %{kind: :given, name: :attach_stream_callback, params: %{}, returns: ":ok"}
  @spec set_stream_callback((Stream.Event.t() -> :ok)) :: :ok
  def set_stream_callback(callback) when is_function(callback, 1) do
    Process.put(:gong_stream_callback, callback)
    :ok
  end

  @doc "清除当前进程的 stream 回调"
  @bdd_instruction %{kind: :given, name: :clear_stream_callback, params: %{}, returns: ":ok"}
  @spec clear_stream_callback() :: :ok
  def clear_stream_callback do
    Process.delete(:gong_stream_callback)
    :ok
  end

  # 发射单个 stream 事件（如有回调则调用）
  defp emit_stream_event(%StreamEvent{} = event) do
    case Process.get(:gong_stream_callback) do
      callback when is_function(callback, 1) -> callback.(event)
      _ -> :ok
    end
  end
end
