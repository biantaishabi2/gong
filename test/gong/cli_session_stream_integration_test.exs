defmodule Gong.CLISessionStreamIntegrationTest do
  use ExUnit.Case, async: false

  alias Gong.CLI
  alias Gong.Session
  alias Gong.Session.Events

  test "CLI 提交并发 steer 命令后，Session stream 满足 command 内强顺序与全局 seq 单调" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-cli-stream-order",
        agent: Gong.Agent.new(),
        llm_backend_fn: fn agent_state, _call_id ->
          message = last_user_message(agent_state)
          Process.sleep(message_delay(message))
          {:ok, {:text, "echo:" <> message}}
        end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = CLI.subscribe_session_stream(session, self())

    {:ok, command_a} =
      CLI.build_command_payload("session-cli-stream-order", "steer", %{message: "A"},
        command_id: "cmd-A"
      )

    {:ok, command_b} =
      CLI.build_command_payload("session-cli-stream-order", "steer", %{message: "B"},
        command_id: "cmd-B"
      )

    {:ok, command_c} =
      CLI.build_command_payload("session-cli-stream-order", "steer", %{message: "C"},
        command_id: "cmd-C"
      )

    tasks =
      [command_a, command_b, command_c]
      |> Enum.map(fn command ->
        Task.async(fn -> CLI.submit_command(session, command) end)
      end)

    assert Enum.all?(tasks, &(Task.await(&1, 1_500) == :ok))

    command_ids = MapSet.new(["cmd-A", "cmd-B", "cmd-C"])
    events = receive_until_all_completed(command_ids, [])

    seqs = Enum.map(events, & &1.seq)
    assert seqs == Enum.sort(seqs)
    assert length(seqs) == MapSet.size(MapSet.new(seqs))

    Enum.each(command_ids, fn command_id ->
      command_events = Enum.filter(events, &(&1.command_id == command_id))
      command_types = Enum.map(command_events, & &1.type)

      assert command_types != []
      assert ordered?(command_types, "lifecycle.received", "lifecycle.processing")
      assert ordered?(command_types, "lifecycle.processing", "lifecycle.turn_started")
      assert ordered?(command_types, "lifecycle.turn_started", "message.start")
      assert ordered?(command_types, "message.start", "message.end")
      assert ordered?(command_types, "message.end", "lifecycle.result")
      assert ordered?(command_types, "lifecycle.result", "lifecycle.completed")

      if "lifecycle.turn_completed" in command_types do
        assert ordered?(command_types, "lifecycle.completed", "lifecycle.turn_completed")
      end
    end)
  end

  test "unsubscribe 成功后取消订阅者不可见后续新事件，且会话可继续" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-cli-stream-unsubscribe",
        agent: Gong.Agent.new(),
        llm_backend_fn: fn agent_state, _call_id ->
          message = last_user_message(agent_state)

          if message == "slow" do
            Process.sleep(120)
          end

          {:ok, {:text, "echo:" <> message}}
        end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    test_process = self()
    shadow_subscriber = spawn_link(fn -> shadow_subscriber_loop(test_process) end)
    on_exit(fn -> send(shadow_subscriber, :stop) end)

    assert :ok = CLI.subscribe_session_stream(session, self())
    assert :ok = CLI.subscribe_session_stream(session, shadow_subscriber)

    {:ok, slow_command} =
      CLI.build_command_payload("session-cli-stream-unsubscribe", "steer", %{message: "slow"},
        command_id: "cmd-slow"
      )

    {:ok, fast_command} =
      CLI.build_command_payload("session-cli-stream-unsubscribe", "steer", %{message: "fast"},
        command_id: "cmd-fast"
      )

    assert :ok = CLI.submit_command(session, slow_command)
    Process.sleep(20)
    assert :ok = CLI.unsubscribe_session_stream(session, shadow_subscriber)
    assert :ok = CLI.submit_command(session, fast_command)

    control_events = receive_until_all_completed(MapSet.new(["cmd-slow", "cmd-fast"]), [])

    assert Enum.any?(
             control_events,
             &(&1.command_id == "cmd-fast" and &1.type == "lifecycle.completed")
           )

    refute_receive {:shadow_event, %{command_id: "cmd-fast"}}, 300
  end

  test "非法 command payload 参数返回统一 invalid_argument 错误" do
    {:ok, session} = Session.start_link(session_id: "session-cli-stream-invalid")
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert {:error, missing_session_id} =
             CLI.submit_command(session, %{
               command_id: "cmd-invalid-1",
               type: "steer",
               args: %{message: "hello"},
               timestamp: System.os_time(:millisecond)
             })

    assert missing_session_id.code == :invalid_argument

    assert {:error, invalid_type} =
             CLI.submit_command(session, %{
               session_id: "session-cli-stream-invalid",
               command_id: "cmd-invalid-2",
               type: "unknown",
               args: %{message: "hello"},
               timestamp: System.os_time(:millisecond)
             })

    assert invalid_type.code == :invalid_argument
  end

  test "消费端遇到重复/逆序 seq 事件时触发顺序校验错误" do
    {:ok, event1} =
      Events.new("lifecycle.received", %{}, %{
        session_id: "session-cli-consumer",
        command_id: "cmd-consumer",
        turn_id: 1,
        seq: 1
      })

    {:ok, event2} =
      Events.new("lifecycle.processing", %{}, %{
        session_id: "session-cli-consumer",
        command_id: "cmd-consumer",
        turn_id: 1,
        seq: 2,
        causation_id: event1.event_id
      })

    cursor = Events.new_cursor(0)
    {:ok, :accepted, cursor} = Events.consume_event(cursor, event1)
    {:ok, :accepted, cursor} = Events.consume_event(cursor, event2)
    assert {:ok, :duplicate, ^cursor} = Events.consume_event(cursor, event2)

    {:ok, out_of_order_event} =
      Events.new("message.start", %{}, %{
        session_id: "session-cli-consumer",
        command_id: "cmd-consumer",
        turn_id: 1,
        seq: 1
      })

    assert {:error, {:sequence_mismatch, %{expected: 3, actual: 1}}} =
             Events.consume_event(cursor, out_of_order_event)
  end

  defp last_user_message(agent_state) do
    alias Jido.Agent.Strategy.State, as: StratState
    state = StratState.get(agent_state, %{})
    conversation = Map.get(state, :conversation, [])
    conversation
    |> Enum.reverse()
    |> Enum.find_value("", fn msg -> if msg[:role] == :user, do: msg[:content] end)
  end

  defp message_delay("A"), do: 40
  defp message_delay("B"), do: 10
  defp message_delay("C"), do: 25
  defp message_delay(_), do: 5

  defp receive_until_all_completed(command_ids, acc) do
    completed_ids =
      acc
      |> Enum.filter(&(&1.type == "lifecycle.completed"))
      |> Enum.map(& &1.command_id)
      |> MapSet.new()

    if MapSet.subset?(command_ids, completed_ids) do
      acc
    else
      receive do
        {:session_event, event} ->
          receive_until_all_completed(command_ids, acc ++ [event])
      after
        2_000 ->
          flunk("等待 lifecycle.completed 事件超时")
      end
    end
  end

  defp ordered?(types, first, second) do
    first_index = Enum.find_index(types, &(&1 == first))
    second_index = Enum.find_index(types, &(&1 == second))

    is_integer(first_index) and is_integer(second_index) and first_index < second_index
  end

  defp shadow_subscriber_loop(parent) do
    receive do
      {:session_event, event} ->
        send(parent, {:shadow_event, event})
        shadow_subscriber_loop(parent)

      :stop ->
        :ok
    end
  end
end
