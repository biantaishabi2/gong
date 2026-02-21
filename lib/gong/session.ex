defmodule Gong.Session do
  @moduledoc """
  Session 协调层（L0 最小稳定契约）。

  对外 API：
  - `start_link/1`
  - `submit_command/3`（标准 command payload，异步）
  - `prompt/3`（异步，立即返回）
  - `subscribe/2`
  - `unsubscribe/2`
  - `history/1`
  - `restore/2`
  - `close/1`
  """

  Module.register_attribute(__MODULE__, :bdd_instruction, accumulate: true)

  use GenServer

  alias Gong.AgentLoop
  alias Gong.AutoCompaction
  alias Gong.ModelRegistry
  alias Gong.Session.Events
  alias Gong.Stream.Event, as: StreamEvent
  alias Gong.Thinking

  require Logger

  @type error_code ::
          :invalid_argument
          | :session_not_found
          | :network_error
          | :rate_limited
          | :internal_error
          | :stream_error
          | :timeout
          | :cancelled
          | :unauthorized

  @type error_t :: %{
          required(:code) => error_code(),
          required(:message) => String.t(),
          required(:retriable) => boolean(),
          required(:retry_after) => integer() | nil,
          required(:details) => map()
        }

  @details_max_depth 8
  @details_max_items 32
  @default_model "deepseek:deepseek-chat"
  @supported_command_types MapSet.new(["prompt", "steer"])

  @type history_entry :: %{
          required(:role) => atom(),
          required(:content) => String.t(),
          required(:turn_id) => non_neg_integer(),
          required(:ts) => integer()
        }


  @type command_payload :: %{
          required(:session_id) => String.t(),
          required(:command_id) => String.t(),
          required(:type) => String.t(),
          required(:args) => map(),
          required(:timestamp) => integer()
        }

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, error_t()}
  def start_link(opts \\ []) do
    # 提前校验 model，避免 init 中 {:stop, reason} 导致 EXIT 信号
    case validate_model_opts(opts) do
      {:error, reason} ->
        {:error, normalize_error(reason)}

      :ok ->
        name = Keyword.get(opts, :name)
        genserver_opts = if name, do: [name: name], else: []

        try do
          case GenServer.start_link(__MODULE__, opts, genserver_opts) do
            {:ok, pid} -> {:ok, pid}
            {:error, reason} -> {:error, normalize_error(reason)}
          end
        rescue
          FunctionClauseError ->
            {:error, normalize_error(:invalid_argument)}

          ArgumentError ->
            {:error, normalize_error(:invalid_argument)}
        catch
          :exit, reason ->
            {:error, normalize_error(normalize_genserver_exit(reason))}
        end
    end
  end

  @doc """
  通过 DynamicSupervisor 启动 Session，并注册到 SessionRegistry。

  由 SessionManager.create_session/1 调用，不影响 start_link/1 的现有行为。
  """
  @spec start_supervised(keyword()) :: {:ok, pid()} | {:error, error_t()}
  def start_supervised(opts) do
    session_id = Keyword.get(opts, :session_id, "session_#{System.unique_integer([:positive, :monotonic])}")
    via_name = {:via, Registry, {Gong.SessionRegistry, session_id}}
    opts = Keyword.put(opts, :name, via_name) |> Keyword.put(:session_id, session_id)
    start_link(opts)
  end

  defp validate_model_opts(opts) do
    model = Keyword.get(opts, :model)
    direct_agent = Keyword.get(opts, :agent)

    cond do
      direct_agent != nil -> :ok
      is_binary(model) ->
        case ModelRegistry.lookup_by_string(model) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
      true -> :ok
    end
  end

  @doc "异步发送 prompt，函数立即返回，结果仅通过事件流回传。"
  @bdd_instruction %{kind: :when, name: :session_prompt_with_model, params: %{message: :string, model: :string}, returns: ":ok | {:error, error}"}
  @spec prompt(pid(), String.t(), keyword()) :: :ok | {:error, error_t()}
  def prompt(pid, message, opts) do
    case safe_genserver_call(pid, {:prompt, message, opts}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @deprecated "请使用 prompt/3"
  @spec prompt(pid(), String.t()) :: :ok | {:error, error_t()}
  def prompt(pid, message), do: prompt(pid, message, [])

  @doc """
  提交标准 command payload。

  payload 要求：
  - `session_id`
  - `command_id`
  - `type`（当前支持 `prompt` / `steer`）
  - `args`（至少包含 `message`）
  - `timestamp`（毫秒）
  """
  @spec submit_command(pid(), command_payload(), keyword()) :: :ok | {:error, error_t()}
  def submit_command(pid, command_payload, opts \\ []) do
    case safe_genserver_call(pid, {:submit_command, command_payload, opts}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @doc """
  订阅 Session 事件流。

  新契约：`subscribe(pid, subscriber_pid)`，事件以 `{:session_event, event}` 下发。
  """
  @spec subscribe(pid(), pid()) :: :ok | {:error, error_t()}
  def subscribe(pid, subscriber) when is_pid(subscriber) do
    case safe_genserver_call(pid, {:subscribe, subscriber}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec subscribe(pid(), (Events.t() -> any())) :: (-> :ok) | {:error, error_t()}
  def subscribe(pid, listener) when is_function(listener, 1) do
    IO.warn("Gong.Session.subscribe/2 传 listener 函数的兼容入口已废弃，请改为 subscribe(pid, subscriber_pid)")

    adapter_pid = spawn_link(fn -> listener_loop(listener) end)

    case subscribe(pid, adapter_pid) do
      :ok ->
        fn ->
          send(adapter_pid, :stop)
          unsubscribe(pid, adapter_pid)
        end

      {:error, _} = error ->
        Process.exit(adapter_pid, :normal)
        error
    end
  end

  def subscribe(_pid, _subscriber), do: {:error, normalize_error(:invalid_argument)}

  @spec unsubscribe(pid(), pid()) :: :ok | {:error, error_t()}
  def unsubscribe(pid, subscriber) when is_pid(subscriber) do
    case safe_genserver_call(pid, {:unsubscribe, subscriber}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  def unsubscribe(_pid, _subscriber), do: {:error, normalize_error(:invalid_argument)}

  @spec history(pid()) :: {:ok, [history_entry()]} | {:error, error_t()}
  def history(pid) do
    case safe_genserver_call(pid, :history) do
      {:ok, history} when is_list(history) -> {:ok, history}
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec metadata(pid()) :: {:ok, map()} | {:error, error_t()}
  def metadata(pid) do
    case safe_genserver_call(pid, :metadata) do
      {:ok, metadata} when is_map(metadata) -> {:ok, metadata}
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @doc """
  查找最后一条有效 assistant 消息文本。

  规则：
  - 仅处理 assistant
  - 忽略空内容
  - 忽略工具调用/工具结果消息
  - 多模态优先提取 text 片段，缺失时回退首个非空片段
  """
  @spec get_last_assistant_message([map()]) :: String.t() | nil
  def get_last_assistant_message(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn message ->
      if assistant_message?(message) and not tool_like_message?(message) do
        message
        |> Map.get(:content, Map.get(message, "content"))
        |> extract_message_text()
      else
        nil
      end
    end)
  end

  def get_last_assistant_message(_), do: nil

  @doc "JS 风格兼容入口（与 get_last_assistant_message/1 等价）"
  @spec getLastAssistantMessage([map()]) :: String.t() | nil
  def getLastAssistantMessage(messages), do: get_last_assistant_message(messages)

  @doc """
  恢复持久核心状态（history/turn_cursor/metadata），不恢复订阅关系。

  `snapshot_or_session_id` 支持：
  - `%{history:, turn_cursor:, metadata:}` 快照（兼容读取 `turn_id`）
  - `session_id` 字符串（通过 `restore_fun` 注入查询）
  """
  @spec restore(pid(), map() | String.t()) ::
          {:ok,
           %{
             session_id: String.t(),
             history: [history_entry()],
             turn_cursor: non_neg_integer(),
             metadata: map()
           }}
          | {:error, error_t()}
  def restore(pid, snapshot_or_session_id) do
    case safe_genserver_call(pid, {:restore, snapshot_or_session_id}) do
      {:ok, {:ok, _} = ok} -> ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @doc "获取累计 Token 用量与成本统计"
  @spec stats(pid()) :: {:ok, map()} | {:error, error_t()}
  def stats(pid) do
    case safe_genserver_call(pid, :stats) do
      {:ok, stats} when is_map(stats) -> {:ok, stats}
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec close(pid()) :: :ok | {:error, error_t()}
  def close(pid) do
    case safe_genserver_stop(pid) do
      :ok -> :ok
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @impl true
  def init(opts) do
    model = Keyword.get(opts, :model)
    restore_fun = Keyword.get(opts, :restore_fun)
    session_id = Keyword.get(opts, :session_id, default_session_id())

    tape_path = Keyword.get(opts, :tape_path)
    auto_compaction = Keyword.get(opts, :auto_compaction)
    workspace = Keyword.get(opts, :workspace, File.cwd!())

    # Agent 路径：model（生产）/ agent+llm_backend_fn（测试直传）/ model+llm_backend_fn（测试覆盖）
    direct_agent = Keyword.get(opts, :agent)
    llm_backend_fn_override = Keyword.get(opts, :llm_backend_fn)

    {agent, llm_backend_fn} =
      cond do
        # 直传 agent（测试用）
        direct_agent != nil ->
          {direct_agent, llm_backend_fn_override}

        # model + llm_backend_fn 覆盖（测试生产 init 路径但 mock LLM）
        is_binary(model) and is_function(llm_backend_fn_override) ->
          case ModelRegistry.lookup_by_string(model) do
            {:ok, _config} -> {Gong.Agent.new(), llm_backend_fn_override}
            {:error, _} -> {Gong.Agent.new(), nil}
          end

        # 正常 model 路径（生产）— 已在 start_link 中校验过
        is_binary(model) ->
          case ModelRegistry.lookup_by_string(model) do
            {:ok, config} -> {Gong.Agent.new(), AgentLoop.build_llm_backend(config)}
            {:error, _} -> {Gong.Agent.new(), nil}
          end

        # 无 model 无 agent（最小启动，如 restore 测试）
        true ->
          {Gong.Agent.new(), nil}
      end

    # 初始化 metadata：记录当前 model 和 thinking level
    init_metadata =
      if is_binary(model) do
        case ModelRegistry.lookup_by_string(model) do
          {:ok, config} ->
            thinking_level = Map.get(config, :thinking_level, "off") |> to_string()
            %{"session" => %{"model" => model, "thinking" => %{"level" => thinking_level}}}

          _ ->
            %{"session" => %{"model" => model, "thinking" => %{"level" => "off"}}}
        end
      else
        %{}
      end

    state = %{
      session_id: session_id,
      agent: agent,
      llm_backend_fn: llm_backend_fn,
      restore_fun: restore_fun,
      tape_path: tape_path,
      auto_compaction: auto_compaction,
      workspace: workspace,
      turn_id: 0,
      metadata: init_metadata,
      subscribers: MapSet.new(),
      monitors: %{},
      subscriber_forwarders: %{},
      session_seq: 0,
      command_last_event_id: %{},
      seen_command_ids: MapSet.new(),
      turn_buffers: %{},
      # Agent 路径串行化：同时只跑一个 AgentLoop.run，后续排队
      agent_busy: false,
      agent_queue: :queue.new(),
      # Token 用量与成本累计统计
      stats: %{
        total_turns: 0,
        total_input_tokens: 0,
        total_output_tokens: 0,
        total_cost: 0.0
      }
    }

    {:ok, state}
  end


  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    if MapSet.member?(state.subscribers, subscriber) do
      {:reply, :ok, state}
    else
      # Process.monitor 支持远程 PID，若进程已死会立即收到 :DOWN
      ref = Process.monitor(subscriber)
      forwarder = spawn(fn -> subscriber_forwarder_loop(subscriber) end)

      new_state =
        state
        |> Map.update!(:subscribers, &MapSet.put(&1, subscriber))
        |> Map.update!(:monitors, &Map.put(&1, subscriber, ref))
        |> Map.update!(:subscriber_forwarders, &Map.put(&1, subscriber, forwarder))

      {:reply, :ok, new_state}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    new_state = unregister_subscriber(state, subscriber)
    {:reply, :ok, new_state}
  end

  def handle_call(:history, _from, state) do
    {:reply, get_history(state), state}
  end

  def handle_call(:metadata, _from, state) do
    {:reply, state.metadata, state}
  end

  def handle_call(:stats, _from, state) do
    {:reply, state.stats, state}
  end

  def handle_call({:restore, source}, _from, state) do
    with {:ok, snapshot} <- load_snapshot(source, state),
         {:ok, restored} <- normalize_snapshot(snapshot, state.session_id) do
      restored_state = %{
        state
        | session_id: restored.session_id,
          turn_id: restored.turn_cursor,
          metadata: restored.metadata,
          command_last_event_id: %{},
          seen_command_ids: MapSet.new(),
          turn_buffers: %{}
      }

      # 将恢复的 history 同步到 Agent Thread
      history_messages =
        Enum.map(restored.history, fn entry ->
          %{
            role: to_string(snapshot_get(entry, :role) || "user"),
            content: snapshot_get(entry, :content) || ""
          }
        end)

      restored_state = replace_agent_conversation(restored_state, history_messages)

      restore_command_id = system_command_id("restore")

      restored_state =
        emit_event(
          restored_state,
          "lifecycle.session_restored",
          %{restored: true},
          nil,
          restore_command_id,
          restored.turn_cursor
        )

      restored_state = cleanup_command_chain(restored_state, restore_command_id)
      clear_subscriber_monitors(restored_state.monitors)
      clear_subscriber_forwarders(restored_state.subscriber_forwarders)

      new_state =
        %{restored_state | subscribers: MapSet.new(), monitors: %{}, subscriber_forwarders: %{}}

      response = %{
        session_id: new_state.session_id,
        history: restored.history,
        turn_cursor: new_state.turn_id,
        metadata: new_state.metadata
      }

      {:reply, {:ok, response}, new_state}
    else
      {:error, reason} ->
        {:reply, {:error, normalize_error(reason)}, state}
    end
  end

  def handle_call({:prompt, message, opts}, _from, state) do
    with :ok <- validate_prompt(message),
         :ok <- validate_prompt_opts(opts),
         :ok <- validate_backend_available(state) do
      command_payload = %{
        session_id: state.session_id,
        command_id: Events.generate_command_id(),
        type: "prompt",
        args: %{message: message},
        timestamp: System.os_time(:millisecond)
      }

      case enqueue_command(state, command_payload, opts) do
        {:ok, new_state} -> {:reply, :ok, new_state}
        {:error, reason} -> {:reply, {:error, normalize_error(reason)}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, normalize_error(reason)}, state}
    end
  end

  def handle_call({:submit_command, command_payload, opts}, _from, state) do
    with :ok <- validate_prompt_opts(opts),
         {:ok, normalized_payload} <- validate_command_payload(command_payload, state),
         :ok <- validate_backend_available(state) do
      case enqueue_command(state, normalized_payload, opts) do
        {:ok, new_state} -> {:reply, :ok, new_state}
        {:error, reason} -> {:reply, {:error, normalize_error(reason)}, state}
      end
    else
      {:error, reason} ->
        {:reply, {:error, normalize_error(reason)}, state}
    end
  end

  @impl true
  def handle_info(
        {:session_stream_event, command_id, turn_id, %StreamEvent{} = stream_event},
        state
      ) do
    state =
      state
      |> maybe_buffer_stream_delta(turn_id, stream_event)
      |> emit_stream_event(stream_event, command_id, turn_id)

    {:noreply, state}
  end

  # Agent 路径：turn 完成，存回 updated_agent，累加 usage，然后检查队列
  def handle_info({:session_turn_done, command_id, turn_id, {:ok_agent, updated_agent, usage}}, state) do
    state = %{state | agent: updated_agent}
    state = accumulate_stats(state, usage)
    state = maybe_dequeue_agent(state)
    handle_turn_ok(state, command_id, turn_id, usage)
  end

  # 兼容旧格式（无 usage）
  def handle_info({:session_turn_done, command_id, turn_id, {:ok_agent, updated_agent}}, state) do
    state = %{state | agent: updated_agent}
    usage = %{input_tokens: 0, output_tokens: 0}
    state = accumulate_stats(state, usage)
    state = maybe_dequeue_agent(state)
    handle_turn_ok(state, command_id, turn_id, usage)
  end

  # Agent 路径：turn 出错，仍存回 updated_agent，累加 usage，然后检查队列
  def handle_info(
        {:session_turn_done, command_id, turn_id, {:error_agent, reason, updated_agent, usage}},
        state
      ) do
    state = %{state | agent: updated_agent}
    state = accumulate_stats(state, usage)
    state = maybe_dequeue_agent(state)
    handle_turn_error(state, command_id, turn_id, reason, usage)
  end

  # 兼容旧格式（无 usage）
  def handle_info(
        {:session_turn_done, command_id, turn_id, {:error_agent, reason, updated_agent}},
        state
      ) do
    state = %{state | agent: updated_agent}
    usage = %{input_tokens: 0, output_tokens: 0}
    state = accumulate_stats(state, usage)
    state = maybe_dequeue_agent(state)
    handle_turn_error(state, command_id, turn_id, reason, usage)
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    new_state =
      if Map.get(state.monitors, pid) == ref do
        unregister_subscriber(state, pid)
      else
        state
      end

    {:noreply, new_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # ── Turn 完成处理 ──

  defp handle_turn_ok(state, command_id, turn_id, usage) do
    {assistant_text, turn_buffers} = Map.pop(state.turn_buffers, turn_id, "")
    state = %{state | turn_buffers: turn_buffers}

    state =
      emit_event(
        state,
        "lifecycle.result",
        %{status: "ok", assistant_text: assistant_text},
        nil,
        command_id,
        turn_id
      )

    # 自动压缩：在 result 之后、completed 之前
    state = maybe_session_compact(state, command_id, turn_id)

    state =
      emit_event(
        state,
        "lifecycle.completed",
        %{status: "ok"},
        nil,
        command_id,
        turn_id
      )

    state =
      emit_event(
        state,
        "lifecycle.turn_completed",
        %{status: "ok", usage: usage},
        nil,
        command_id,
        turn_id
      )

    # 每轮完成后自动保存
    maybe_auto_save(state)

    {:noreply, cleanup_command_chain(state, command_id)}
  end

  defp handle_turn_error(state, command_id, turn_id, reason, usage) do
    normalized_error = normalize_error(reason)
    state = emit_runtime_error(state, command_id, turn_id, reason)

    state =
      emit_event(
        state,
        "lifecycle.error",
        %{status: "error"},
        normalized_error,
        command_id,
        turn_id
      )

    state =
      emit_event(
        state,
        "lifecycle.completed",
        %{status: "error"},
        nil,
        command_id,
        turn_id
      )

    state =
      emit_event(
        state,
        "lifecycle.turn_completed",
        %{status: "error", usage: usage},
        nil,
        command_id,
        turn_id
      )

    state =
      state
      |> Map.update!(:turn_buffers, &Map.delete(&1, turn_id))
      |> cleanup_command_chain(command_id)

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # 自动持久化：如果有 tape_path 且 history 非空，保存快照
    maybe_auto_save(state)

    close_command_id = system_command_id("close")

    _ =
      emit_event(
        state,
        "lifecycle.session_closed",
        %{reason: inspect(reason)},
        nil,
        close_command_id,
        max(state.turn_id, 0)
      )

    :ok
  end

  @doc false
  @spec normalize_error(term()) :: error_t()
  def normalize_error(%{code: code} = err) do
    code = normalize_code(code)
    details = normalize_error_details(Map.get(err, :details, %{}))
    retry_after = normalize_retry_after(Map.get(err, :retry_after), code)

    %{
      code: code,
      message: normalize_error_message(Map.get(err, :message, inspect(err))),
      retriable: retriable?(code, details, Map.get(err, :retriable)),
      retry_after: retry_after,
      details: details
    }
  end

  def normalize_error({:error, reason}), do: normalize_error(reason)

  def normalize_error({:rate_limited, retry_after, details}) do
    %{
      code: :rate_limited,
      message: "rate limited",
      retriable: true,
      retry_after: normalize_retry_after(retry_after, :rate_limited),
      details: normalize_error_details(details)
    }
  end

  def normalize_error({:internal_error, subtype, message}) do
    details = %{subtype: to_string(subtype)}

    %{
      code: :internal_error,
      message: normalize_error_message(message),
      retriable: retriable?(:internal_error, details, nil),
      retry_after: nil,
      details: details
    }
  end

  def normalize_error({:stream_error, message, details}) do
    %{
      code: :stream_error,
      message: normalize_error_message(message),
      retriable: true,
      retry_after: nil,
      details: normalize_error_details(details)
    }
  end

  def normalize_error(:invalid_argument), do: error(:invalid_argument, "invalid argument", %{})
  def normalize_error(:session_not_found), do: error(:session_not_found, "session not found", %{})
  def normalize_error(:network_error), do: error(:network_error, "network error", %{})
  def normalize_error(:timeout), do: error(:timeout, "timeout", %{})
  def normalize_error(:cancelled), do: error(:cancelled, "cancelled", %{})
  def normalize_error(:unauthorized), do: error(:unauthorized, "unauthorized", %{})

  def normalize_error(other) do
    error(:internal_error, "internal error", %{raw: inspect(other)})
  end

  defp maybe_auto_save(%{tape_path: tape_path} = state)
       when is_binary(tape_path) and tape_path != "" do
    history = get_history(state)

    if history != [] do
      snapshot = build_auto_save_snapshot(state)

      try do
        Gong.CLI.SessionCmd.save_session(tape_path, state.session_id, snapshot)
      rescue
        e ->
          Logger.warning("Session auto-save 失败: #{Exception.message(e)}")
      end
    end
  end

  defp maybe_auto_save(_state), do: :ok

  defp build_auto_save_snapshot(state) do
    history = get_history(state)

    %{
      "session_id" => state.session_id,
      "history" => Enum.map(history, fn entry ->
        %{
          "role" => to_string(snapshot_get(entry, :role) || "user"),
          "content" => snapshot_get(entry, :content) || "",
          "turn_id" => snapshot_get(entry, :turn_id) || 0,
          "ts" => snapshot_get(entry, :ts) || System.os_time(:millisecond)
        }
      end),
      "turn_cursor" => state.turn_id,
      "metadata" => state.metadata
    }
  end

  # 自动压缩：将 history 转为消息格式后调 AutoCompaction
  defp maybe_session_compact(%{auto_compaction: nil} = state, _command_id, _turn_id), do: state
  defp maybe_session_compact(%{auto_compaction: compaction_opts} = state, command_id, turn_id) do
    history = get_history(state)

    messages = Enum.map(history, fn entry ->
      %{role: to_string(snapshot_get(entry, :role) || "user"),
        content: snapshot_get(entry, :content) || ""}
    end)

    case AutoCompaction.auto_compact(messages, compaction_opts) do
      {:compacted, new_messages, summary} ->
        # 将压缩后消息写回 Agent Thread
        state = replace_agent_conversation(state, new_messages)

        emit_event(
          state,
          "lifecycle.compaction_done",
          %{summary: summary, before_count: length(messages), after_count: length(new_messages)},
          nil,
          command_id,
          turn_id
        )

      {:no_action, _} ->
        state

      {:skipped, _} ->
        state
    end
  end

  # 累加 usage 到 session stats
  defp accumulate_stats(state, usage) when is_map(usage) do
    # 非负约束：防止异常负值导致累计 token/cost 被错误减少
    input = max(Map.get(usage, :input_tokens, 0) || 0, 0)
    output = max(Map.get(usage, :output_tokens, 0) || 0, 0)

    # 获取当前 model 用于计算成本
    model = get_in(state.metadata, ["session", "model"]) || "unknown"
    cost = Gong.CostTracker.calculate_cost(model, input, output)

    stats = state.stats
    updated_stats = %{
      total_turns: stats.total_turns + 1,
      total_input_tokens: stats.total_input_tokens + input,
      total_output_tokens: stats.total_output_tokens + output,
      total_cost: stats.total_cost + cost
    }

    %{state | stats: updated_stats}
  end

  defp accumulate_stats(state, _usage), do: state

  defp emit_runtime_error(state, command_id, turn_id, reason) do
    envelope = normalize_error(reason)
    emit_event(state, "error.runtime", %{}, envelope, command_id, turn_id)
  end

  defp emit_stream_event(state, stream_event, command_id, turn_id) do
    {ctx, state} = next_event_ctx(state, command_id, turn_id)

    case Events.from_stream_event(stream_event, ctx) do
      {:ok, event} ->
        state
        |> record_emitted_event(command_id, event)
        |> dispatch_event(event)

      {:error, reason} ->
        emit_runtime_error(state, command_id, turn_id, {:stream_error, inspect(reason), %{}})
    end
  end

  defp emit_event(state, type, payload, error, command_id, turn_id) do
    {ctx, state} = next_event_ctx(state, command_id, turn_id)

    case Events.new(type, payload, ctx, error) do
      {:ok, event} ->
        state
        |> record_emitted_event(command_id, event)
        |> dispatch_event(event)

      {:error, _reason} ->
        state
    end
  end

  defp next_event_ctx(state, command_id, turn_id) do
    {seq, state} = next_seq(state)

    ctx = %{
      session_id: state.session_id,
      command_id: command_id,
      turn_id: turn_id,
      seq: seq,
      causation_id: Map.get(state.command_last_event_id, command_id)
    }

    {ctx, state}
  end

  defp record_emitted_event(state, command_id, event) do
    put_in(state, [:command_last_event_id, command_id], event.event_id)
  end

  defp cleanup_command_chain(state, command_id) do
    update_in(state, [:command_last_event_id], &Map.delete(&1, command_id))
  end

  defp dispatch_event(state, event) do
    Enum.each(state.subscriber_forwarders, fn {_subscriber, forwarder} ->
      send(forwarder, {:session_event, event})
    end)

    state
  end

  defp maybe_buffer_stream_delta(state, turn_id, %StreamEvent{type: :text_delta, content: content}) do
    delta_content = normalize_stream_delta_content(content)

    Map.update(state, :turn_buffers, %{turn_id => delta_content}, fn buffers ->
      Map.update(buffers, turn_id, delta_content, fn existing ->
        (existing || "") <> delta_content
      end)
    end)
  end

  defp maybe_buffer_stream_delta(state, _turn_id, _stream_event), do: state

  defp normalize_stream_delta_content(content) when is_binary(content), do: content
  defp normalize_stream_delta_content(nil), do: ""

  defp normalize_stream_delta_content(content) do
    try do
      to_string(content)
    rescue
      _ -> inspect(content)
    end
  end

  defp next_seq(state) do
    next = Events.next_seq(state.session_seq)
    {next, %{state | session_seq: next}}
  end

  defp validate_prompt(message) when is_binary(message) do
    if String.trim(message) == "", do: {:error, :invalid_argument}, else: :ok
  end

  defp validate_prompt(_), do: {:error, :invalid_argument}

  defp validate_backend_available(%{llm_backend_fn: nil}), do: {:error, :unauthorized}
  defp validate_backend_available(_state), do: :ok

  defp validate_prompt_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_argument}
  end

  defp validate_prompt_opts(_), do: {:error, :invalid_argument}

  defp validate_command_payload(command_payload, expected_session_id)
       when is_map(command_payload) and is_binary(expected_session_id) do
    with session_id when is_binary(session_id) <- payload_get(command_payload, :session_id),
         true <- session_id == expected_session_id and session_id != "",
         command_id when is_binary(command_id) <- payload_get(command_payload, :command_id),
         true <- String.trim(command_id) != "",
         type when is_binary(type) <- payload_get(command_payload, :type),
         true <- MapSet.member?(@supported_command_types, type),
         args when is_map(args) <- payload_get(command_payload, :args),
         timestamp when is_integer(timestamp) <- payload_get(command_payload, :timestamp),
         true <- timestamp > 0,
         {:ok, _message} <- extract_command_message(args) do
      {:ok,
       %{
         session_id: session_id,
         command_id: command_id,
         type: type,
         args: args,
         timestamp: timestamp
       }}
    else
      _ -> {:error, :invalid_argument}
    end
  end

  defp validate_command_payload(command_payload, state) when is_map(command_payload) and is_map(state) do
    with {:ok, normalized_payload} <- validate_command_payload(command_payload, state.session_id),
         true <- command_id_available?(state, normalized_payload.command_id) do
      {:ok, normalized_payload}
    else
      false -> {:error, :invalid_argument}
      {:error, _reason} -> {:error, :invalid_argument}
    end
  end

  defp validate_command_payload(_command_payload, _state), do: {:error, :invalid_argument}

  defp command_id_available?(state, command_id) do
    not Map.has_key?(state.command_last_event_id, command_id) and
      not MapSet.member?(state.seen_command_ids, command_id)
  end

  defp extract_command_message(args) when is_map(args) do
    message = payload_get(args, :message)

    cond do
      is_binary(message) and String.trim(message) != "" ->
        {:ok, message}

      true ->
        {:error, :invalid_argument}
    end
  end

  defp extract_command_message(_args), do: {:error, :invalid_argument}

  defp enqueue_command(state, command_payload, _run_opts) do
    with {:ok, message} <- extract_command_message(command_payload.args) do
      turn_id = state.turn_id + 1

      state =
        state
        |> Map.put(:turn_id, turn_id)
        |> Map.put(:seen_command_ids, MapSet.put(state.seen_command_ids, command_payload.command_id))
        |> put_in([:turn_buffers, turn_id], "")

      state =
        emit_event(
          state,
          "lifecycle.received",
          %{
            command_type: command_payload.type,
            command_timestamp: command_payload.timestamp,
            async: true
          },
          nil,
          command_payload.command_id,
          turn_id
        )

      state =
        emit_event(
          state,
          "lifecycle.processing",
          %{command_type: command_payload.type, delivery: "best_effort_at_least_once"},
          nil,
          command_payload.command_id,
          turn_id
        )

      state =
        emit_event(
          state,
          "lifecycle.turn_started",
          %{async: true, delivery: "best_effort_at_least_once"},
          nil,
          command_payload.command_id,
          turn_id
        )

      session_pid = self()
      command_id = command_payload.command_id

      # Agent 直调路径：串行化，同时只跑一个 AgentLoop.run
      queued_item = {message, command_id, turn_id}

      state =
        if state.agent_busy do
          # 上一轮还在跑，排队等待
          %{state | agent_queue: :queue.in(queued_item, state.agent_queue)}
        else
          # 空闲，立即启动
          start_agent_task(state, queued_item, session_pid)
        end

      {:ok, state}
    end
  end

  # Agent 直调路径：调用 AgentLoop.run，从进程字典读取 usage
  defp run_agent_turn(session_pid, agent, message, llm_backend_fn, command_id, turn_id, opts \\ []) do
    agent_opts = [llm_backend: llm_backend_fn] ++ opts
    case AgentLoop.run(agent, message, agent_opts) do
      {:ok, _reply, updated_agent} ->
        usage = Process.get(:gong_turn_usage, %{input_tokens: 0, output_tokens: 0})
        send(session_pid, {:session_turn_done, command_id, turn_id, {:ok_agent, updated_agent, usage}})

      {:error, reason, updated_agent} ->
        usage = Process.get(:gong_turn_usage, %{input_tokens: 0, output_tokens: 0})
        send(
          session_pid,
          {:session_turn_done, command_id, turn_id, {:error_agent, reason, updated_agent, usage}}
        )
    end
  end

  # 启动 Agent Task（标记 busy）
  defp start_agent_task(state, {message, command_id, turn_id}, session_pid) do
    agent = state.agent
    llm_backend_fn = state.llm_backend_fn
    workspace = state.workspace

    Task.start(fn ->
      Gong.AgentLoop.set_stream_callback(fn event ->
        count = Process.get(:gong_stream_callback_count, 0)
        Process.put(:gong_stream_callback_count, count + 1)
        send(session_pid, {:session_stream_event, command_id, turn_id, event})
      end)

      run_agent_turn(session_pid, agent, message, llm_backend_fn, command_id, turn_id, workspace: workspace)
    end)

    %{state | agent_busy: true}
  end

  # 上一轮完成后，检查队列中是否有等待的任务
  defp maybe_dequeue_agent(state) do
    case :queue.out(state.agent_queue) do
      {{:value, queued_item}, remaining_queue} ->
        state = %{state | agent_queue: remaining_queue}
        start_agent_task(state, queued_item, self())

      {:empty, _} ->
        %{state | agent_busy: false}
    end
  end

  defp payload_get(map, key), do: Events.payload_get(map, key)

  defp load_snapshot(snapshot, _state) when is_map(snapshot) do
    {:ok, snapshot}
  end

  defp load_snapshot(session_id, %{restore_fun: restore_fun})
       when is_binary(session_id) and is_function(restore_fun, 1) do
    case restore_fun.(session_id) do
      {:ok, snapshot} when is_map(snapshot) -> {:ok, snapshot}
      {:error, _} = error -> error
      nil -> {:error, :session_not_found}
      other when is_map(other) -> {:ok, other}
      _ -> {:error, :invalid_argument}
    end
  end

  defp load_snapshot(session_id, _state) when is_binary(session_id),
    do: {:error, :session_not_found}

  defp load_snapshot(_, _state), do: {:error, :invalid_argument}

  defp normalize_snapshot(snapshot, fallback_session_id) do
    history = normalize_snapshot_history(snapshot)
    turn_cursor = normalize_snapshot_turn_cursor(snapshot)
    metadata = normalize_snapshot_metadata(snapshot_get(snapshot, :metadata))
    session_id = normalize_snapshot_session_id(snapshot, fallback_session_id)

    model = resolve_snapshot_model(snapshot, metadata)
    thinking_level = resolve_snapshot_thinking_level(snapshot, metadata)
    metadata = normalize_metadata_for_write(metadata, model, thinking_level)

    {:ok,
     %{
       history: history,
       turn_cursor: turn_cursor,
       metadata: metadata,
       session_id: session_id
     }}
  end

  defp normalize_snapshot_history(snapshot) do
    case snapshot_get(snapshot, :history) do
      history when is_list(history) ->
        history

      nil ->
        []

      other ->
        Logger.warning("Session restore: history 格式无效，回退空数组，值=#{inspect(other)}")
        []
    end
  end

  defp normalize_snapshot_turn_cursor(snapshot) do
    raw_turn_cursor = snapshot_get(snapshot, :turn_cursor)
    raw_turn_id = snapshot_get(snapshot, :turn_id)

    case normalize_non_negative_integer(raw_turn_cursor) do
      {:ok, turn_cursor} ->
        turn_cursor

      :error ->
        case normalize_non_negative_integer(raw_turn_id) do
          {:ok, turn_id} ->
            if not is_nil(raw_turn_cursor) do
              Logger.warning(
                "Session restore: turn_cursor 格式无效，改用 turn_id，turn_cursor=#{inspect(raw_turn_cursor)}，turn_id=#{inspect(raw_turn_id)}"
              )
            end

            turn_id

          :error ->
            if not (is_nil(raw_turn_cursor) and is_nil(raw_turn_id)) do
              Logger.warning(
                "Session restore: turn_cursor/turn_id 格式无效，回退 0，turn_cursor=#{inspect(raw_turn_cursor)}，turn_id=#{inspect(raw_turn_id)}"
              )
            end

            0
        end
    end
  end

  defp normalize_snapshot_session_id(snapshot, fallback_session_id) do
    case snapshot_get(snapshot, :session_id) do
      session_id when is_binary(session_id) and session_id != "" ->
        session_id

      nil ->
        fallback_session_id

      other ->
        Logger.warning("Session restore: session_id 格式无效，使用默认 session_id，值=#{inspect(other)}")
        fallback_session_id
    end
  end

  defp normalize_snapshot_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_snapshot_metadata(nil), do: %{}

  defp normalize_snapshot_metadata(other) do
    Logger.warning("Session restore: metadata 格式无效，回退空 map，值=#{inspect(other)}")
    %{}
  end

  defp resolve_snapshot_model(snapshot, metadata) do
    model =
      pick_model_value(
        [
          {"snapshot.session.model", nested_get(snapshot, [:session, :model])},
          {"snapshot.model", snapshot_get(snapshot, :model)},
          {"metadata.session.model", nested_get(metadata, [:session, :model])}
        ],
        :new
      ) ||
        pick_model_value(
          [
            {"snapshot.saved_model", snapshot_get(snapshot, :saved_model)},
            {"snapshot.savedModel", snapshot_get(snapshot, :savedModel)},
            {"snapshot.model_name", snapshot_get(snapshot, :model_name)},
            {"snapshot.modelName", snapshot_get(snapshot, :modelName)},
            {"metadata.initial_state.model", nested_get(metadata, [:initial_state, :model])},
            {"metadata.model", snapshot_get(metadata, :model)}
          ],
          :legacy
        ) ||
        @default_model

    model
  end

  defp resolve_snapshot_thinking_level(snapshot, metadata) do
    new_level =
      pick_thinking_value(
        [
          {"snapshot.session.thinking.level",
           nested_get(snapshot, [:session, :thinking, :level])},
          {"snapshot.thinking.level", nested_get(snapshot, [:thinking, :level])},
          {"metadata.session.thinking.level",
           nested_get(metadata, [:session, :thinking, :level])},
          {"metadata.thinking.level", nested_get(metadata, [:thinking, :level])}
        ],
        :new
      )

    legacy_level =
      pick_thinking_value(
        [
          {"snapshot.thinking_level", snapshot_get(snapshot, :thinking_level)},
          {"snapshot.thinkingLevel", snapshot_get(snapshot, :thinkingLevel)},
          {"snapshot.savedThinkingLevel", snapshot_get(snapshot, :savedThinkingLevel)},
          {"snapshot.saved_thinking_level", snapshot_get(snapshot, :saved_thinking_level)},
          {"metadata.initial_state.thinking_level",
           nested_get(metadata, [:initial_state, :thinking_level])},
          {"metadata.thinking_level", snapshot_get(metadata, :thinking_level)},
          {"metadata.thinkingLevel", snapshot_get(metadata, :thinkingLevel)}
        ],
        :legacy
      )

    {resolved_level, source} =
      Thinking.restore_level(new_level, legacy_level, Thinking.default_level())

    if source == :default and new_level == nil and legacy_level == nil do
      Logger.warning("Session restore: thinking level 缺失，回退默认值 #{resolved_level}")
    end

    Atom.to_string(resolved_level)
  end

  defp normalize_metadata_for_write(metadata, model, thinking_level) do
    canonical_session =
      metadata
      |> snapshot_get(:session)
      |> normalize_snapshot_metadata()
      |> drop_legacy_session_keys()
      |> Map.put("model", model)
      |> Map.put("thinking", %{"level" => thinking_level})

    metadata
    |> Map.drop([
      :session,
      :model,
      "model",
      :model_name,
      "model_name",
      :modelName,
      "modelName",
      :saved_model,
      "saved_model",
      :savedModel,
      "savedModel",
      :thinking,
      "thinking",
      :thinking_level,
      "thinking_level",
      :thinkingLevel,
      "thinkingLevel",
      :savedThinkingLevel,
      "savedThinkingLevel",
      :saved_thinking_level,
      "saved_thinking_level"
    ])
    |> Map.put("session", canonical_session)
  end

  defp drop_legacy_session_keys(session) when is_map(session) do
    Map.drop(session, [
      :model,
      "model",
      :model_name,
      "model_name",
      :modelName,
      "modelName",
      :saved_model,
      "saved_model",
      :savedModel,
      "savedModel",
      :thinking,
      "thinking",
      :thinking_level,
      "thinking_level",
      :thinkingLevel,
      "thinkingLevel",
      :savedThinkingLevel,
      "savedThinkingLevel",
      :saved_thinking_level,
      "saved_thinking_level"
    ])
  end

  defp pick_model_value(candidates, source) do
    Enum.find_value(candidates, fn {label, value} ->
      case normalize_model_value(value) do
        {:ok, model} ->
          model

        :error when is_nil(value) ->
          nil

        :error ->
          Logger.warning(
            "Session restore: #{source} model 字段格式无效，已忽略，来源=#{label}，值=#{inspect(value)}"
          )

          nil
      end
    end)
  end

  defp pick_thinking_value(candidates, source) do
    Enum.find_value(candidates, fn {label, value} ->
      case Thinking.normalize_level(value) do
        {:ok, level} ->
          level

        {:error, :invalid_level} when is_nil(value) ->
          nil

        {:error, :invalid_level} ->
          Logger.warning(
            "Session restore: #{source} thinking 字段格式无效，已忽略，来源=#{label}，值=#{inspect(value)}"
          )

          nil
      end
    end)
  end

  defp normalize_model_value(value) when is_binary(value) do
    model = String.trim(value)

    cond do
      model == "" ->
        :error

      String.contains?(model, ":") ->
        normalize_model_pair(model, ":")

      String.contains?(model, "/") ->
        normalize_model_pair(model, "/")

      true ->
        :error
    end
  end

  defp normalize_model_value(%{} = model) do
    provider = snapshot_get(model, :provider)

    model_id =
      snapshot_get(model, :model_id) || snapshot_get(model, :modelId) || snapshot_get(model, :id)

    with provider when is_binary(provider) <- provider,
         model_id when is_binary(model_id) <- model_id do
      provider = String.trim(provider)
      model_id = String.trim(model_id)

      if provider != "" and model_id != "" do
        {:ok, "#{provider}:#{model_id}"}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp normalize_model_value(_), do: :error

  defp normalize_model_pair(model, separator) when is_binary(model) and is_binary(separator) do
    case String.split(model, separator, parts: 2) do
      [provider, model_id] ->
        provider = String.trim(provider)
        model_id = String.trim(model_id)

        if provider != "" and model_id != "" do
          {:ok, "#{provider}:#{model_id}"}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0,
    do: {:ok, value}

  defp normalize_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> {:ok, parsed}
      _ -> :error
    end
  end

  defp normalize_non_negative_integer(_), do: :error

  defp snapshot_get(nil, _key), do: nil

  defp snapshot_get(map, key) when is_map(map) and is_atom(key) do
    string_key = Atom.to_string(key)

    case Map.fetch(map, string_key) do
      {:ok, value} -> value
      :error -> Map.get(map, key)
    end
  end

  defp snapshot_get(map, key) when is_map(map) and is_binary(key) do
    Map.get(map, key)
  end

  defp snapshot_get(_other, _key), do: nil

  defp nested_get(map, []), do: map

  defp nested_get(map, [key | rest]) do
    map
    |> snapshot_get(key)
    |> nested_get(rest)
  end

  # ── 最后 assistant 消息提取 ──

  defp assistant_message?(message) when is_map(message) do
    role = snapshot_get(message, :role)
    role in [:assistant, "assistant"]
  end

  defp assistant_message?(_), do: false

  defp tool_like_message?(message) when is_map(message) do
    role = snapshot_get(message, :role)
    has_tool_calls = snapshot_get(message, :tool_calls) not in [nil, []]
    content = snapshot_get(message, :content)

    role in [:tool, "tool", :tool_result, "tool_result", :tool_call, "tool_call"] or
      has_tool_calls or tool_content_only?(content)
  end

  defp tool_like_message?(_), do: false

  defp tool_content_only?(content) when is_list(content) do
    effective_parts =
      content
      |> Enum.map(&normalize_content_part/1)
      |> Enum.reject(&is_nil/1)

    effective_parts != [] and
      Enum.all?(
        effective_parts,
        &(&1.type in [:tool_call, "tool_call", :tool_result, "tool_result"])
      )
  end

  defp tool_content_only?(_), do: false

  defp extract_message_text(content) do
    cond do
      is_binary(content) ->
        trim_to_nil(content)

      is_list(content) ->
        extract_text_from_parts(content) || extract_fallback_from_parts(content)

      is_map(content) ->
        extract_text_from_part(content) || extract_fallback_from_part(content)

      true ->
        nil
    end
  end

  defp extract_text_from_parts(parts) do
    texts =
      parts
      |> Enum.map(&extract_text_from_part/1)
      |> Enum.reject(&is_nil/1)

    case texts do
      [] -> nil
      values -> Enum.join(values, "\n")
    end
  end

  defp extract_text_from_part(part) when is_map(part) do
    type = snapshot_get(part, :type)

    if type in [:text, "text"] do
      snapshot_get(part, :text)
      |> trim_to_nil()
    else
      nil
    end
  end

  defp extract_text_from_part(_), do: nil

  defp extract_fallback_from_parts(parts) do
    Enum.find_value(parts, &extract_fallback_from_part/1)
  end

  defp extract_fallback_from_part(part) when is_binary(part), do: trim_to_nil(part)

  defp extract_fallback_from_part(part) when is_map(part) do
    if tool_content_part?(part) do
      nil
    else
      candidate =
        snapshot_get(part, :text) ||
          snapshot_get(part, :content) ||
          snapshot_get(part, :value)

      trim_to_nil(candidate)
    end
  end

  defp extract_fallback_from_part(_), do: nil

  defp normalize_content_part(part) when is_map(part) do
    %{
      type: snapshot_get(part, :type),
      text: snapshot_get(part, :text),
      content: snapshot_get(part, :content),
      value: snapshot_get(part, :value)
    }
  end

  defp normalize_content_part(_), do: nil

  defp tool_content_part?(part) when is_map(part) do
    type = snapshot_get(part, :type)
    type in [:tool_call, "tool_call", :tool_result, "tool_result"]
  end

  defp tool_content_part?(_), do: false

  defp trim_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trim_to_nil(_), do: nil

  defp listener_loop(listener) do
    receive do
      {:session_event, event} ->
        # 兼容层监听器失败不能影响 Session 主流程
        safe_invoke_listener(listener, event)
        listener_loop(listener)

      :stop ->
        :ok
    end
  end

  defp unregister_subscriber(state, subscriber) do
    {ref, monitors} = Map.pop(state.monitors, subscriber)
    {forwarder, forwarders} = Map.pop(state.subscriber_forwarders, subscriber)

    if is_reference(ref), do: Process.demonitor(ref, [:flush])
    stop_subscriber_forwarder(forwarder)

    state
    |> Map.put(:monitors, monitors)
    |> Map.update!(:subscribers, &MapSet.delete(&1, subscriber))
    |> Map.put(:subscriber_forwarders, forwarders)
  end

  defp stop_subscriber_forwarder(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :normal)
  end

  defp stop_subscriber_forwarder(_), do: :ok

  defp subscriber_forwarder_loop(subscriber) do
    receive do
      {:session_event, event} ->
        send(subscriber, {:session_event, event})
        subscriber_forwarder_loop(subscriber)

      :stop ->
        :ok
    end
  end

  defp safe_invoke_listener(listener, event) do
    try do
      _ = listener.(event)
      :ok
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end
  end

  defp clear_subscriber_monitors(monitors) do
    Enum.each(monitors, fn {_pid, ref} ->
      Process.demonitor(ref, [:flush])
    end)
  end

  defp clear_subscriber_forwarders(forwarders) do
    Enum.each(forwarders, fn {_subscriber, forwarder} ->
      stop_subscriber_forwarder(forwarder)
    end)
  end

  # 替换 Agent 的对话内容（用于压缩/恢复）
  defp replace_agent_conversation(state, messages) do
    alias Jido.Agent.Strategy.State, as: StratState
    strat_state = StratState.get(state.agent, %{})

    # 转为 Agent conversation 格式（atom role）
    new_conversation =
      Enum.map(messages, fn msg ->
        role = msg[:role] || msg["role"] || "user"
        content = msg[:content] || msg["content"] || ""
        %{role: to_role_atom(role), content: content}
      end)

    # 重建 Thread
    new_thread = rebuild_thread(new_conversation)

    updated_strat = strat_state
      |> Map.put(:conversation, new_conversation)
      |> Map.put(:thread, new_thread)
      # 重置状态为 completed 以便下一轮走 do_start_continue
      |> Map.put(:status, "completed")

    updated_agent = StratState.put(state.agent, updated_strat)
    %{state | agent: updated_agent}
  end

  defp to_role_atom(role) when is_atom(role), do: role
  defp to_role_atom("user"), do: :user
  defp to_role_atom("assistant"), do: :assistant
  defp to_role_atom("system"), do: :system
  defp to_role_atom("tool"), do: :tool
  defp to_role_atom(_), do: :user

  defp rebuild_thread(conversation) do
    alias Jido.AI.Thread

    {system_prompt, rest} =
      case conversation do
        [%{role: :system, content: content} | rest] -> {content, rest}
        _ -> {nil, conversation}
      end

    Thread.new(system_prompt: system_prompt)
    |> Thread.append_messages(rest)
  end

  # 从 Agent Thread 获取对话历史
  defp get_history(state) do
    agent_conversation(state.agent)
  end

  # 从 Agent 提取 conversation 并转为 history 格式
  defp agent_conversation(agent) do
    alias Jido.Agent.Strategy.State, as: StratState
    state = StratState.get(agent, %{})
    conversation = Map.get(state, :conversation, [])

    conversation
    |> Enum.reject(fn msg -> msg[:role] == :system end)
    |> Enum.with_index(1)
    |> Enum.map(fn {msg, idx} ->
      %{
        role: msg[:role] || :user,
        content: msg[:content] || "",
        turn_id: div(idx + 1, 2),
        ts: System.os_time(:millisecond)
      }
    end)
  end

  defp default_session_id do
    "session_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp system_command_id(prefix) when is_binary(prefix) do
    "system:" <>
      prefix <> ":" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end

  defp error(code, message, details) do
    %{
      code: code,
      message: message,
      retriable: retriable?(code, details, nil),
      retry_after: normalize_retry_after(nil, code),
      details: details
    }
  end

  defp retriable?(:network_error, _details, _), do: true
  defp retriable?(:rate_limited, _details, _), do: true
  defp retriable?(:stream_error, _details, _), do: true
  defp retriable?(:timeout, _details, _), do: true

  defp retriable?(:internal_error, details, _) do
    subtype = Map.get(details, :subtype, Map.get(details, "subtype"))
    to_string(subtype) in ["upstream_unavailable", "transport_reset"]
  end

  defp retriable?(_code, _details, _), do: false

  defp normalize_code(code) when code in ~w(
         invalid_argument
         session_not_found
         network_error
         rate_limited
         internal_error
         stream_error
         timeout
         cancelled
         unauthorized
       )a,
    do: code

  defp normalize_code(code) when is_binary(code) do
    case code do
      "invalid_argument" -> :invalid_argument
      "session_not_found" -> :session_not_found
      "network_error" -> :network_error
      "rate_limited" -> :rate_limited
      "internal_error" -> :internal_error
      "stream_error" -> :stream_error
      "timeout" -> :timeout
      "cancelled" -> :cancelled
      "unauthorized" -> :unauthorized
      _ -> :internal_error
    end
  end

  defp normalize_code(_), do: :internal_error

  defp normalize_retry_after(value, :rate_limited) when is_integer(value) and value >= 0,
    do: value

  defp normalize_retry_after(_value, :rate_limited), do: 1
  defp normalize_retry_after(_value, _code), do: nil

  # 限制 details 的深度与宽度，避免极端嵌套导致序列化/日志开销失控
  defp normalize_error_details(details) when is_map(details) do
    sanitize_map(details, 0)
  end

  defp normalize_error_details(_), do: %{}

  defp sanitize_map(_map, depth) when depth >= @details_max_depth do
    %{truncated: true}
  end

  defp sanitize_map(map, depth) do
    map
    |> Enum.take(@details_max_items)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, key, sanitize_detail_value(value, depth + 1))
    end)
  end

  defp sanitize_detail_value(_value, depth) when depth >= @details_max_depth, do: "[truncated]"

  defp sanitize_detail_value(value, depth) when is_map(value) do
    sanitize_map(value, depth)
  end

  defp sanitize_detail_value(value, depth) when is_list(value) do
    value
    |> Enum.take(@details_max_items)
    |> Enum.map(&sanitize_detail_value(&1, depth + 1))
  end

  defp sanitize_detail_value(value, _depth)
       when is_binary(value) or is_boolean(value) or is_integer(value) or is_float(value) or
              is_atom(value) or is_nil(value) do
    value
  end

  defp sanitize_detail_value(value, _depth), do: inspect(value)

  defp normalize_error_message(message) when is_binary(message), do: message
  defp normalize_error_message(message), do: inspect(message)

  defp safe_genserver_call(pid, message) do
    try do
      {:ok, GenServer.call(pid, message)}
    rescue
      FunctionClauseError ->
        {:error, :invalid_argument}

      ArgumentError ->
        {:error, :invalid_argument}
    catch
      :exit, reason ->
        {:error, normalize_genserver_exit(reason)}
    end
  end

  defp safe_genserver_stop(pid) do
    try do
      GenServer.stop(pid, :normal)
      :ok
    rescue
      FunctionClauseError ->
        {:error, :invalid_argument}

      ArgumentError ->
        {:error, :invalid_argument}
    catch
      :exit, reason ->
        {:error, normalize_genserver_exit(reason)}
    end
  end

  defp normalize_genserver_exit({:noproc, _}), do: :session_not_found
  defp normalize_genserver_exit({:normal, _}), do: :session_not_found
  defp normalize_genserver_exit({:shutdown, _}), do: :session_not_found
  defp normalize_genserver_exit({:timeout, _}), do: :timeout
  defp normalize_genserver_exit(:noproc), do: :session_not_found
  defp normalize_genserver_exit(:normal), do: :session_not_found
  defp normalize_genserver_exit(:timeout), do: :timeout
  defp normalize_genserver_exit(other), do: {:internal_error, :session_call_exit, inspect(other)}
end
