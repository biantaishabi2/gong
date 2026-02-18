defmodule Gong.Session.Events do
  @moduledoc """
  Session 统一事件模型（schema_version=1.0.0）。

  事件字段固定为：
  - `schema_version`
  - `event_id`（UUIDv7）
  - `session_id`
  - `turn_id`
  - `seq`
  - `ts`
  - `type`
  - `payload`
  - `error`
  """

  import Bitwise

  alias Gong.Stream.Event, as: StreamEvent

  @schema_version "1.0.0"
  @uuid_v7_regex ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  @event_types MapSet.new([
                 "lifecycle.session_restored",
                 "lifecycle.session_closed",
                 "lifecycle.turn_started",
                 "lifecycle.turn_completed",
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
          turn_id: non_neg_integer(),
          seq: pos_integer(),
          ts: integer(),
          type: event_type(),
          payload: map(),
          error: map() | nil
        }

  defstruct [
    :event_id,
    :session_id,
    :turn_id,
    :seq,
    :ts,
    :type,
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

  @doc "创建 Session 事件"
  @spec new(event_type(), map(), map(), map() | nil) :: {:ok, t()} | {:error, term()}
  def new(type, payload, ctx, error \\ nil) do
    with true <- event_type?(type),
         :ok <- validate_ctx(ctx),
         true <- is_map(payload),
         true <- is_nil(error) or is_map(error) do
      event = %__MODULE__{
        event_id: uuid_v7(),
        session_id: ctx.session_id,
        turn_id: ctx.turn_id,
        seq: ctx.seq,
        ts: System.os_time(:millisecond),
        type: type,
        payload: payload,
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

  def from_stream_event(%StreamEvent{type: :tool_end, tool_name: tool_name}, ctx, _error) do
    new("tool.end", %{tool_name: tool_name}, ctx, nil)
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
         true <- is_integer(event.turn_id) and event.turn_id >= 0,
         true <- is_integer(event.seq) and event.seq > 0,
         true <- is_integer(event.ts) and event.ts > 0,
         true <- event_type?(event.type),
         true <- is_map(event.payload),
         true <- is_nil(event.error) or is_map(event.error) do
      {:ok, event}
    else
      false -> {:error, :invalid_event}
    end
  end

  defp validate_ctx(%{session_id: session_id, turn_id: turn_id, seq: seq})
       when is_binary(session_id) and session_id != "" and is_integer(turn_id) and turn_id >= 0 and
              is_integer(seq) and seq > 0 do
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
