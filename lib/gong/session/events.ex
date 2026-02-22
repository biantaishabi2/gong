defmodule Gong.Session.Events do
  @moduledoc """
  Session 统一事件模型（schema_version=1.0.0）。

  事件字段固定为：
  - `schema_version`
  - `event_id`（UUIDv7）
  - `session_id`
  - `command_id`
  - `turn_id`
  - `seq`
  - `occurred_at`
  - `ts`（兼容字段，等于 `occurred_at`）
  - `type`
  - `payload`
  - `causation_id`
  - `error`
  """

  import Bitwise

  alias Gong.Stream.Event, as: StreamEvent

  @schema_version "1.0.0"
  @uuid_v7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  # lifecycle.session_closed payload 字段：
  #   - reason :: String.t() — 关闭原因（manual | ttl_idle_expired | ttl_absolute_expired | lru_evicted | fatal_error）
  #   - duration_ms :: integer() — 会话存活时长（毫秒）

  @event_types MapSet.new([
                 "lifecycle.session_restored",
                 "lifecycle.session_closed",
                 "lifecycle.turn_started",
                 "lifecycle.turn_completed",
                 "lifecycle.received",
                 "lifecycle.processing",
                 "lifecycle.result",
                 "lifecycle.error",
                 "lifecycle.completed",
                 "lifecycle.compaction_done",
                 "message.start",
                 "message.delta",
                 "message.end",
                 "tool.start",
                 "tool.delta",
                 "tool.end",
                 "error.stream",
                 "error.runtime"
               ])

  @type event_type :: String.t()

  @type t :: %__MODULE__{
          schema_version: String.t(),
          event_id: String.t(),
          session_id: String.t(),
          command_id: String.t(),
          turn_id: non_neg_integer(),
          seq: pos_integer(),
          occurred_at: integer(),
          ts: integer(),
          type: event_type(),
          payload: map(),
          causation_id: String.t() | nil,
          error: map() | nil
        }

  @type consumer_cursor :: %{
          required(:last_seq) => non_neg_integer(),
          required(:seen_event_ids) => MapSet.t(String.t())
        }

  defstruct [
    :event_id,
    :session_id,
    :command_id,
    :turn_id,
    :seq,
    :occurred_at,
    :ts,
    :type,
    :causation_id,
    payload: %{},
    error: nil,
    schema_version: @schema_version
  ]

  @doc "schema 版本号"
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "是否为支持的事件类型"
  @spec event_type?(term()) :: boolean()
  def event_type?(type), do: MapSet.member?(@event_types, type)

  @doc "生成 command_id（供 CLI/兼容入口构建 command payload）"
  @spec generate_command_id() :: String.t()
  def generate_command_id, do: "cmd_" <> uuid_v7()

  @doc "从上一个 seq 计算下一个 seq（session 全局单调）"
  @spec next_seq(non_neg_integer()) :: pos_integer()
  def next_seq(last_seq) when is_integer(last_seq) and last_seq >= 0, do: last_seq + 1

  @doc "创建 Session 事件"
  @spec new(event_type(), map(), map(), map() | nil) :: {:ok, t()} | {:error, term()}
  def new(type, payload, ctx, error \\ nil) do
    occurred_at = Map.get(ctx, :occurred_at, System.os_time(:millisecond))
    turn_id = Map.get(ctx, :turn_id, 0)
    causation_id = Map.get(ctx, :causation_id)

    with true <- event_type?(type),
         :ok <- validate_ctx(ctx),
         true <- is_map(payload),
         true <- is_integer(turn_id) and turn_id >= 0,
         true <- is_integer(occurred_at) and occurred_at > 0,
         true <-
           is_nil(causation_id) or
             (is_binary(causation_id) and Regex.match?(@uuid_v7_regex, causation_id)),
         true <- is_nil(error) or is_map(error) do
      event = %__MODULE__{
        event_id: uuid_v7(),
        session_id: ctx.session_id,
        command_id: ctx.command_id,
        turn_id: turn_id,
        seq: ctx.seq,
        occurred_at: occurred_at,
        ts: occurred_at,
        type: type,
        payload: payload,
        causation_id: causation_id,
        error: error
      }

      validate(event)
    else
      false -> {:error, :invalid_argument}
      {:error, _} = error -> error
    end
  end

  @doc """
  将 Stream.Event 归一为 Session 事件。

  说明：Stream 层仅负责 chunk 规范化与序列校验，前端语义统一在本模块归一。
  """
  @spec from_stream_event(StreamEvent.t(), map()) :: {:ok, t()} | {:error, term()}
  def from_stream_event(stream_event, ctx), do: from_stream_event(stream_event, ctx, nil)

  @spec from_stream_event(StreamEvent.t(), map(), map() | nil) :: {:ok, t()} | {:error, term()}
  def from_stream_event(%StreamEvent{type: :text_start}, ctx, _error) do
    new("message.start", %{}, ctx, nil)
  end

  def from_stream_event(%StreamEvent{type: :text_delta, content: content}, ctx, _error) do
    new("message.delta", %{content: content || ""}, ctx, nil)
  end

  def from_stream_event(%StreamEvent{type: :text_end}, ctx, _error) do
    new("message.end", %{}, ctx, nil)
  end

  def from_stream_event(
        %StreamEvent{type: :tool_start, tool_name: tool_name, tool_args: tool_args},
        ctx,
        _error
      ) do
    new("tool.start", %{tool_name: tool_name, tool_args: tool_args || %{}}, ctx, nil)
  end

  def from_stream_event(
        %StreamEvent{type: :tool_delta, content: content, tool_name: tool_name},
        ctx,
        _error
      ) do
    new("tool.delta", %{tool_name: tool_name, content: content || ""}, ctx, nil)
  end

  def from_stream_event(
        %StreamEvent{type: :tool_end, tool_name: tool_name, content: content, success: success},
        ctx,
        _error
      ) do
    new("tool.end", %{tool_name: tool_name, result: content || "", success: success != false}, ctx, nil)
  end

  def from_stream_event(%StreamEvent{type: :error, content: content}, ctx, error) do
    normalized_error =
      if is_map(error) do
        error
      else
        %{
          code: :stream_error,
          message: content || "stream error",
          retriable: true,
          retry_after: nil,
          details: %{}
        }
      end

    new("error.stream", %{}, ctx, normalized_error)
  end

  def from_stream_event(_event, _ctx, _meta), do: {:error, :unsupported_stream_event}

  @doc "校验事件结构"
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = event) do
    with true <- event.schema_version == @schema_version,
         true <- is_binary(event.event_id) and Regex.match?(@uuid_v7_regex, event.event_id),
         true <- is_binary(event.session_id) and event.session_id != "",
         true <- is_binary(event.command_id) and event.command_id != "",
         true <- is_integer(event.turn_id) and event.turn_id >= 0,
         true <- is_integer(event.seq) and event.seq > 0,
         true <- is_integer(event.occurred_at) and event.occurred_at > 0,
         true <- is_integer(event.ts) and event.ts > 0,
         true <- event.ts == event.occurred_at,
         true <- event_type?(event.type),
         true <- is_map(event.payload),
         true <- is_nil(event.causation_id) or Regex.match?(@uuid_v7_regex, event.causation_id),
         true <- is_nil(event.error) or is_map(event.error) do
      {:ok, event}
    else
      false -> {:error, :invalid_event}
    end
  end

  @doc "事件幂等键（前端/网关可用于幂等去重）"
  @spec idempotency_key(t()) :: String.t()
  def idempotency_key(%__MODULE__{} = event) do
    "#{event.session_id}:#{event.command_id}:#{event.seq}:#{event.type}"
  end

  @doc "创建消费游标（用于断点续读与顺序校验）"
  @spec new_cursor(non_neg_integer()) :: consumer_cursor()
  def new_cursor(last_seq \\ 0)

  def new_cursor(last_seq) when is_integer(last_seq) and last_seq >= 0 do
    %{last_seq: last_seq, seen_event_ids: MapSet.new()}
  end

  @doc """
  消费单条事件并更新游标。

  - 已见过 `event_id`：返回 `:duplicate`
  - `seq` 严格等于 `last_seq + 1`：返回 `:accepted`
  - 否则返回顺序错误，消费端可触发重拉/缓冲策略
  """
  @spec consume_event(consumer_cursor(), t()) ::
          {:ok, :accepted | :duplicate, consumer_cursor()} | {:error, term()}
  def consume_event(%{last_seq: last_seq, seen_event_ids: seen} = cursor, %__MODULE__{} = event)
      when is_integer(last_seq) and last_seq >= 0 do
    with {:ok, event} <- validate(event),
         true <- MapSet.member?(seen, event.event_id) == false do
      expected = last_seq + 1

      if event.seq == expected do
        next_cursor = %{
          cursor
          | last_seq: event.seq,
            seen_event_ids: MapSet.put(seen, event.event_id)
        }

        {:ok, :accepted, next_cursor}
      else
        {:error,
         {:sequence_mismatch, %{expected: expected, actual: event.seq, event_id: event.event_id}}}
      end
    else
      false ->
        {:ok, :duplicate, cursor}

      {:error, _} = error ->
        error
    end
  end

  def consume_event(_cursor, _event), do: {:error, :invalid_consumer_cursor}

  @doc """
  校验事件列表顺序（严格模式）：
  - 禁止重复 `event_id`
  - `seq` 必须连续递增（支持指定起始 seq）
  """
  @spec validate_sequence([t()], non_neg_integer()) :: :ok | {:error, term()}
  def validate_sequence(events, start_seq \\ 0)

  def validate_sequence(events, start_seq)
      when is_list(events) and is_integer(start_seq) and start_seq >= 0 do
    cursor = new_cursor(start_seq)

    Enum.reduce_while(events, {:ok, cursor}, fn event, {:ok, acc_cursor} ->
      case consume_event(acc_cursor, event) do
        {:ok, :accepted, next_cursor} ->
          {:cont, {:ok, next_cursor}}

        {:ok, :duplicate, _cursor} ->
          {:halt, {:error, {:duplicate_event_id, event.event_id}}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, _cursor} -> :ok
      {:error, _} = error -> error
    end
  end

  def validate_sequence(_events, _start_seq), do: {:error, :invalid_argument}

  @doc "从 map 中按 atom key 或 string key 取值（兼容混合键 map）"
  @spec payload_get(map(), atom()) :: term()
  def payload_get(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp validate_ctx(%{session_id: session_id, command_id: command_id, seq: seq})
       when is_binary(session_id) and session_id != "" and is_binary(command_id) and
              command_id != "" and is_integer(seq) and seq > 0 do
    :ok
  end

  defp validate_ctx(_), do: {:error, :invalid_event_context}

  # 生成 UUIDv7（time-ordered，便于消费端去重和排序）
  defp uuid_v7 do
    ts = System.os_time(:millisecond)

    <<r1::8, r2::8, r3::8, r4::8, r5::8, r6::8, r7::8, r8::8, r9::8, r10::8>> =
      :crypto.strong_rand_bytes(10)

    b6 = bor(0x70, band(r1, 0x0F))
    b8 = bor(0x80, band(r3, 0x3F))

    uuid_bin =
      <<ts::48, b6::8, r2::8, b8::8, r4::8, r5::8, r6::8, r7::8, r8::8, r9::8, r10::8>>

    encode_uuid(uuid_bin)
  end

  defp encode_uuid(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    [
      Base.encode16(a, case: :lower),
      Base.encode16(b, case: :lower),
      Base.encode16(c, case: :lower),
      Base.encode16(d, case: :lower),
      Base.encode16(e, case: :lower)
    ]
    |> Enum.join("-")
  end
end
