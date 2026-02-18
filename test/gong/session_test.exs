defmodule Gong.SessionTest do
  use ExUnit.Case, async: false

  alias Gong.Session
  alias Gong.Session.Events

  test "初始化后订阅事件流，turn 内 seq 单调递增且满足 schema 1.0.0" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-seq",
        backend: fn _message, _opts, _ctx -> {:ok, [{:chunk, "hello"}, :done]} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "hello", [])

    events = receive_until_turn_completed([])
    turn_events = Enum.filter(events, &(&1.turn_id == 1))

    assert turn_events != []
    assert Enum.all?(turn_events, &(&1.schema_version == Events.schema_version()))
    assert Enum.map(turn_events, & &1.seq) == Enum.sort(Enum.map(turn_events, & &1.seq))
    assert Enum.any?(turn_events, &(&1.type == "message.end"))
    assert List.last(turn_events).type == "lifecycle.turn_completed"
  end

  test "无订阅者触发事件不会崩溃，且后续请求可继续" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-no-subscriber",
        backend: fn _message, _opts, _ctx -> {:ok, [{:chunk, "pong"}, :done]} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.prompt(session, "ping", [])
    assert wait_until(fn -> length(Session.history(session)) >= 2 end)
    assert Process.alive?(session)

    assert :ok = Session.prompt(session, "ping-again", [])
    assert wait_until(fn -> length(Session.history(session)) >= 4 end)
    assert Process.alive?(session)
  end

  test "restore 仅恢复核心状态，不恢复订阅关系" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-restore",
        backend: fn _message, _opts, _ctx -> {:ok, [{:chunk, "ok"}, :done]} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    snapshot = %{
      history: [%{role: :user, content: "old", turn_id: 7, ts: 1}],
      turn_id: 7,
      metadata: %{"lang" => "zh"}
    }

    assert {:ok, restored} = Session.restore(session, snapshot)
    assert restored.turn_id == 7
    assert restored.metadata == %{"lang" => "zh"}
    assert restored.history == snapshot.history

    # restore 后订阅关系应被清空
    assert :ok = Session.prompt(session, "not-received", [])
    refute_receive {:session_event, _}, 150

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "received", [])

    events = receive_until_turn_completed([])
    assert Enum.all?(events, &(&1.turn_id == 9))
  end

  test "限流错误语义：rate_limited + retriable + retry_after(秒)" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-rate-limit",
        backend: fn _message, _opts, _ctx -> {:error, {:rate_limited, 2, %{provider: "mock"}}} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "trigger", [])

    events = receive_until_turn_completed([])
    error_event = Enum.find(events, &(&1.type == "error.runtime"))

    assert error_event != nil
    assert error_event.payload.code == :rate_limited
    assert error_event.payload.retriable == true
    assert error_event.payload.retry_after == 2
  end

  defp receive_until_turn_completed(acc) do
    receive do
      {:session_event, event} ->
        next = acc ++ [event]

        if event.type == "lifecycle.turn_completed" do
          next
        else
          receive_until_turn_completed(next)
        end
    after
      1_000 ->
        flunk("等待 Session 事件超时")
    end
  end

  defp wait_until(fun, retries \\ 30)

  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, retries) do
    if fun.() do
      true
    else
      Process.sleep(20)
      wait_until(fun, retries - 1)
    end
  end
end
