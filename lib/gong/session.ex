defmodule Gong.Session do
  @moduledoc """
  Session 协调层（L0 最小稳定契约）。

  对外 API：
  - `start_link/1`
  - `prompt/3`（异步，立即返回）
  - `subscribe/2`
  - `unsubscribe/2`
  - `history/1`
  - `restore/2`
  - `close/1`
  """

  use GenServer

  alias Gong.Session.Events
  alias Gong.Stream
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

  @type history_entry :: %{
          required(:role) => atom(),
          required(:content) => String.t(),
          required(:turn_id) => non_neg_integer(),
          required(:ts) => integer()
        }

  @typedoc "Backend 回调：返回 stream chunks / stream events / 文本"
  @type backend_fun ::
          (String.t(), keyword(), map() ->
             {:ok, [StreamEvent.t()] | list() | String.t() | map()} | {:error, term()})

  @spec start_link(keyword()) :: {:ok, pid()} | {:error, error_t()}
  def start_link(opts \\ []) do
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

  @doc "异步发送 prompt，函数立即返回，结果仅通过事件流回传。"
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

  @spec close(pid()) :: :ok | {:error, error_t()}
  def close(pid) do
    case safe_genserver_stop(pid) do
      :ok -> :ok
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @impl true
  def init(opts) do
    backend = Keyword.get(opts, :backend, &__MODULE__.default_backend/3)
    restore_fun = Keyword.get(opts, :restore_fun)
    session_id = Keyword.get(opts, :session_id, default_session_id())

    state = %{
      session_id: session_id,
      backend: backend,
      restore_fun: restore_fun,
      turn_id: 0,
      history: [],
      metadata: %{},
      subscribers: MapSet.new(),
      monitors: %{},
      seq_by_turn: %{},
      turn_buffers: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, subscriber}, _from, state) do
    if Process.alive?(subscriber) do
      if MapSet.member?(state.subscribers, subscriber) do
        {:reply, :ok, state}
      else
        ref = Process.monitor(subscriber)

        new_state =
          state
          |> Map.update!(:subscribers, &MapSet.put(&1, subscriber))
          |> put_in([:monitors, subscriber], ref)

        {:reply, :ok, new_state}
      end
    else
      {:reply, {:error, normalize_error(:invalid_argument)}, state}
    end
  end

  def handle_call({:unsubscribe, subscriber}, _from, state) do
    state =
      case Map.pop(state.monitors, subscriber) do
        {nil, _} ->
          state

        {ref, monitors} ->
          Process.demonitor(ref, [:flush])
          %{state | monitors: monitors}
      end

    new_state = Map.update!(state, :subscribers, &MapSet.delete(&1, subscriber))
    {:reply, :ok, new_state}
  end

  def handle_call(:history, _from, state) do
    {:reply, state.history, state}
  end

  def handle_call({:restore, source}, _from, state) do
    with {:ok, snapshot} <- load_snapshot(source, state),
         {:ok, restored} <- normalize_snapshot(snapshot, state.session_id) do
      restored_state = %{
        state
        | session_id: restored.session_id,
          history: restored.history,
          turn_id: restored.turn_cursor,
          metadata: restored.metadata,
          seq_by_turn: %{},
          turn_buffers: %{}
      }

      restored_state =
        emit_event(
          restored_state,
          "lifecycle.session_restored",
          %{restored: true},
          nil,
          restored.turn_cursor
        )

      clear_subscriber_monitors(restored_state.monitors)

      new_state = %{restored_state | subscribers: MapSet.new(), monitors: %{}}

      response = %{
        session_id: new_state.session_id,
        history: new_state.history,
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
         {:ok, backend} <- resolve_backend(opts, state.backend) do
      turn_id = state.turn_id + 1

      state =
        state
        |> Map.put(:turn_id, turn_id)
        |> Map.update!(:history, fn history ->
          history ++ [history_entry(:user, message, turn_id)]
        end)
        |> put_in([:turn_buffers, turn_id], "")

      state =
        emit_event(
          state,
          "lifecycle.turn_started",
          %{async: true, delivery: "best_effort_at_least_once"},
          nil,
          turn_id
        )

      run_opts = Keyword.delete(opts, :backend)
      session_pid = self()

      Task.start(fn ->
        run_turn(session_pid, backend, message, run_opts, %{
          session_id: state.session_id,
          turn_id: turn_id,
          history: state.history,
          metadata: state.metadata
        })
      end)

      {:reply, :ok, state}
    else
      {:error, reason} ->
        {:reply, {:error, normalize_error(reason)}, state}
    end
  end

  @impl true
  def handle_info({:session_stream_event, turn_id, %StreamEvent{} = stream_event}, state) do
    {seq, state} = next_seq(state, turn_id)

    ctx = %{session_id: state.session_id, turn_id: turn_id, seq: seq}

    case Events.from_stream_event(stream_event, ctx) do
      {:ok, event} ->
        state =
          state
          |> maybe_buffer_stream_delta(turn_id, stream_event)
          |> dispatch_event(event)

        {:noreply, state}

      {:error, reason} ->
        state = emit_runtime_error(state, turn_id, {:stream_error, inspect(reason), %{}})
        {:noreply, state}
    end
  end

  def handle_info({:session_turn_done, turn_id, :ok}, state) do
    {assistant_text, turn_buffers} = Map.pop(state.turn_buffers, turn_id, "")
    state = %{state | turn_buffers: turn_buffers}

    state =
      if assistant_text == "" do
        state
      else
        Map.update!(state, :history, fn history ->
          history ++ [history_entry(:assistant, assistant_text, turn_id)]
        end)
      end

    state =
      emit_event(
        state,
        "lifecycle.turn_completed",
        %{status: "ok"},
        nil,
        turn_id
      )

    {:noreply, state}
  end

  def handle_info({:session_turn_done, turn_id, {:error, reason}}, state) do
    state = emit_runtime_error(state, turn_id, reason)

    state =
      emit_event(
        state,
        "lifecycle.turn_completed",
        %{status: "error"},
        nil,
        turn_id
      )

    {:noreply, %{state | turn_buffers: Map.delete(state.turn_buffers, turn_id)}}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    monitors =
      case Map.get(state.monitors, pid) do
        ^ref -> Map.delete(state.monitors, pid)
        _ -> state.monitors
      end

    new_state = %{state | monitors: monitors, subscribers: MapSet.delete(state.subscribers, pid)}
    {:noreply, new_state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    _ =
      emit_event(
        state,
        "lifecycle.session_closed",
        %{reason: inspect(reason)},
        nil,
        max(state.turn_id, 0)
      )

    :ok
  end

  @doc false
  @spec default_backend(String.t(), keyword(), map()) :: {:error, error_t()}
  def default_backend(_message, _opts, _ctx) do
    {:error, normalize_error(:unauthorized)}
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

  defp run_turn(session_pid, backend, message, opts, context) do
    case call_backend(backend, message, opts, context) do
      {:ok, stream_events} ->
        Enum.each(stream_events, fn stream_event ->
          send(session_pid, {:session_stream_event, context.turn_id, stream_event})
        end)

        send(session_pid, {:session_turn_done, context.turn_id, :ok})

      {:error, reason} ->
        send(session_pid, {:session_turn_done, context.turn_id, {:error, reason}})
    end
  end

  defp call_backend(backend, message, opts, context) do
    try do
      case backend.(message, opts, context) do
        {:ok, result} ->
          normalize_backend_result(result)

        {:error, _} = error ->
          error

        other ->
          {:error, {:internal_error, :invalid_backend_response, inspect(other)}}
      end
    rescue
      e ->
        {:error, {:internal_error, :backend_exception, Exception.message(e)}}
    catch
      kind, reason ->
        {:error, {:internal_error, :backend_exception, "#{kind}: #{inspect(reason)}"}}
    end
  end

  defp normalize_backend_result(result) when is_binary(result) do
    {:ok,
     [
       StreamEvent.new(:text_start),
       StreamEvent.new(:text_delta, content: result),
       StreamEvent.new(:text_end)
     ]}
  end

  defp normalize_backend_result(%{events: events}) when is_list(events) do
    normalize_stream_events(events)
  end

  defp normalize_backend_result(%{chunks: chunks}) when is_list(chunks) do
    chunks
    |> Stream.chunks_to_events()
    |> normalize_stream_events()
  end

  defp normalize_backend_result(result) when is_list(result) do
    cond do
      Enum.all?(result, &match?(%StreamEvent{}, &1)) ->
        normalize_stream_events(result)

      true ->
        result
        |> Stream.chunks_to_events()
        |> normalize_stream_events()
    end
  end

  defp normalize_backend_result(other) do
    {:error, {:internal_error, :invalid_backend_response, inspect(other)}}
  end

  defp normalize_stream_events(events) do
    if Stream.valid_sequence?(events) do
      {:ok, events}
    else
      {:error, {:stream_error, "invalid stream sequence", %{}}}
    end
  end

  defp emit_runtime_error(state, turn_id, reason) do
    envelope = normalize_error(reason)
    emit_event(state, "error.runtime", %{}, envelope, turn_id)
  end

  defp emit_event(state, type, payload, error, turn_id) do
    {seq, state} = next_seq(state, turn_id)
    ctx = %{session_id: state.session_id, turn_id: turn_id, seq: seq}

    case Events.new(type, payload, ctx, error) do
      {:ok, event} -> dispatch_event(state, event)
      {:error, _reason} -> state
    end
  end

  defp dispatch_event(state, event) do
    Enum.each(state.subscribers, fn subscriber ->
      send(subscriber, {:session_event, event})
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

  defp next_seq(state, turn_id) do
    next = Map.get(state.seq_by_turn, turn_id, 0) + 1
    {next, put_in(state, [:seq_by_turn, turn_id], next)}
  end

  defp validate_prompt(message) when is_binary(message) do
    if String.trim(message) == "", do: {:error, :invalid_argument}, else: :ok
  end

  defp validate_prompt(_), do: {:error, :invalid_argument}

  defp validate_prompt_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, :invalid_argument}
  end

  defp validate_prompt_opts(_), do: {:error, :invalid_argument}

  defp resolve_backend(opts, default_backend) do
    case Keyword.get(opts, :backend, default_backend) do
      fun when is_function(fun, 3) -> {:ok, fun}
      _ -> {:error, :invalid_argument}
    end
  end

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

    with provider when is_binary(provider) and provider != "" <- provider,
         model_id when is_binary(model_id) and model_id != "" <- model_id do
      {:ok, "#{provider}:#{model_id}"}
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
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
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

  defp history_entry(role, content, turn_id) do
    %{
      role: role,
      content: content,
      turn_id: turn_id,
      ts: System.os_time(:millisecond)
    }
  end

  defp default_session_id do
    "session_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
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
