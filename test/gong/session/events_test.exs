defmodule Gong.Session.EventsTest do
  use ExUnit.Case, async: true

  alias Gong.Session.Events

  test "new/4 生成完整事件信封" do
    ctx = %{
      session_id: "session-events",
      command_id: "cmd-events-1",
      turn_id: 1,
      seq: 1,
      occurred_at: 1_700_000_000_000
    }

    assert {:ok, event} = Events.new("lifecycle.received", %{source: "cli"}, ctx)
    assert event.schema_version == Events.schema_version()
    assert event.session_id == "session-events"
    assert event.command_id == "cmd-events-1"
    assert event.turn_id == 1
    assert event.seq == 1
    assert event.occurred_at == 1_700_000_000_000
    assert event.ts == event.occurred_at
    assert event.causation_id == nil
    assert is_binary(event.event_id)
  end

  test "因果链与幂等键可追踪同一 command 生命周期" do
    assert {:ok, received} =
             Events.new("lifecycle.received", %{}, %{
               session_id: "session-events",
               command_id: "cmd-events-2",
               turn_id: 2,
               seq: 1
             })

    assert {:ok, processing} =
             Events.new("lifecycle.processing", %{}, %{
               session_id: "session-events",
               command_id: "cmd-events-2",
               turn_id: 2,
               seq: 2,
               causation_id: received.event_id
             })

    assert processing.causation_id == received.event_id

    assert Events.idempotency_key(processing) ==
             "session-events:cmd-events-2:2:lifecycle.processing"
  end

  test "validate_sequence 对正常递增序列返回 :ok" do
    {:ok, e1} =
      Events.new("lifecycle.received", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-3",
        turn_id: 3,
        seq: 1
      })

    {:ok, e2} =
      Events.new("message.start", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-3",
        turn_id: 3,
        seq: 2,
        causation_id: e1.event_id
      })

    {:ok, e3} =
      Events.new("lifecycle.completed", %{status: "ok"}, %{
        session_id: "session-events",
        command_id: "cmd-events-3",
        turn_id: 3,
        seq: 3,
        causation_id: e2.event_id
      })

    assert :ok = Events.validate_sequence([e1, e2, e3])
  end

  test "validate_sequence 在重复或逆序时返回错误" do
    {:ok, e1} =
      Events.new("lifecycle.received", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-4",
        turn_id: 4,
        seq: 1
      })

    {:ok, e2} =
      Events.new("lifecycle.processing", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-4",
        turn_id: 4,
        seq: 2,
        causation_id: e1.event_id
      })

    assert {:error, {:duplicate_event_id, _event_id}} = Events.validate_sequence([e1, e1])

    assert {:error, {:sequence_mismatch, %{expected: 3, actual: 1}}} =
             Events.validate_sequence([e2, e1], 1)
  end

  test "consume_event 支持断点续读和顺序异常检测" do
    cursor = Events.new_cursor(0)

    {:ok, e1} =
      Events.new("lifecycle.received", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-5",
        turn_id: 5,
        seq: 1
      })

    {:ok, :accepted, cursor} = Events.consume_event(cursor, e1)
    assert {:ok, :duplicate, ^cursor} = Events.consume_event(cursor, e1)

    {:ok, e3} =
      Events.new("lifecycle.completed", %{}, %{
        session_id: "session-events",
        command_id: "cmd-events-5",
        turn_id: 5,
        seq: 3,
        causation_id: e1.event_id
      })

    assert {:error, {:sequence_mismatch, %{expected: 2, actual: 3}}} =
             Events.consume_event(cursor, e3)
  end

  test "缺失 command_id 的事件上下文校验失败" do
    assert {:error, :invalid_event_context} =
             Events.new("lifecycle.received", %{}, %{session_id: "session-events", seq: 1})
  end
end
