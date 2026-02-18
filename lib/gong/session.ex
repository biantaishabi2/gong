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

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    genserver_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, genserver_opts)
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

  @spec unsubscribe(pid(), pid()) :: :ok | {:error, error_t()}
  def unsubscribe(pid, subscriber) when is_pid(subscriber) do
    case safe_genserver_call(pid, {:unsubscribe, subscriber}) do
      {:ok, :ok} -> :ok
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

  @spec history(pid()) :: {:ok, [history_entry()]} | {:error, error_t()}
  def history(pid) do
    case safe_genserver_call(pid, :history) do
      {:ok, history} when is_list(history) -> {:ok, history}
      {:ok, {:error, _} = error} -> error
      {:error, reason} -> {:error, normalize_error(reason)}
    end
  end

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
      message: to_string(Map.get(err, :message, inspect(err))),
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
      message: to_string(message),
      retriable: retriable?(:internal_error, details, nil),
      retry_after: nil,
      details: details
    }
  end

  def normalize_error({:stream_error, message, details}) do
    %{
      code: :stream_error,
      message: to_string(message),
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
    Map.update(state, :turn_buffers, %{turn_id => content || ""}, fn buffers ->
      Map.update(buffers, turn_id, content || "", fn existing -> existing <> (content || "") end)
    end)
  end

  defp maybe_buffer_stream_delta(state, _turn_id, _stream_event), do: state

  defp next_seq(state, turn_id) do
    next = Map.get(state.seq_by_turn, turn_id, 0) + 1
    {next, put_in(state, [:seq_by_turn, turn_id], next)}
  end

  defp validate_prompt(message) when is_binary(message) do
    if String.trim(message) == "", do: {:error, :invalid_argument}, else: :ok
  end

  defp validate_prompt(_), do: {:error, :invalid_argument}

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
    history =
      Map.get(snapshot, :history, Map.get(snapshot, "history", []))

    turn_cursor =
      Map.get(
        snapshot,
        :turn_cursor,
        Map.get(snapshot, "turn_cursor", Map.get(snapshot, :turn_id, Map.get(snapshot, "turn_id", 0)))
      )

    metadata =
      Map.get(snapshot, :metadata, Map.get(snapshot, "metadata", %{}))

    session_id =
      Map.get(snapshot, :session_id, Map.get(snapshot, "session_id", fallback_session_id))

    with true <- is_list(history),
         true <- is_integer(turn_cursor) and turn_cursor >= 0,
         true <- is_map(metadata),
         true <- is_binary(session_id) and session_id != "" do
      {:ok,
       %{
         history: history,
         turn_cursor: turn_cursor,
         metadata: metadata,
         session_id: session_id
       }}
    else
      false -> {:error, :invalid_argument}
    end
  end

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

  defp retriable?(_code, _details, explicit) when is_boolean(explicit), do: explicit

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

  defp safe_genserver_call(pid, message) do
    try do
      {:ok, GenServer.call(pid, message)}
    catch
      :exit, reason ->
        {:error, normalize_genserver_exit(reason)}
    end
  end

  defp safe_genserver_stop(pid) do
    try do
      GenServer.stop(pid, :normal)
      :ok
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
