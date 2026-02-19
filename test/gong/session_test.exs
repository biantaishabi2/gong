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
    assert Enum.all?(turn_events, &Map.has_key?(&1, :error))
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
    assert wait_until(fn -> history_len_at_least?(session, 2) end)
    assert Process.alive?(session)

    assert :ok = Session.prompt(session, "ping-again", [])
    assert wait_until(fn -> history_len_at_least?(session, 4) end)
    assert Process.alive?(session)
  end

  test "restore 发送 session_restored 事件且仅恢复核心状态，不恢复订阅关系" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-restore",
        backend: fn _message, _opts, _ctx -> {:ok, [{:chunk, "ok"}, :done]} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    snapshot = %{
      history: [%{role: :user, content: "old", turn_id: 7, ts: 1}],
      turn_cursor: 7,
      metadata: %{"lang" => "zh"}
    }

    assert {:ok, restored} = Session.restore(session, snapshot)
    assert restored.turn_cursor == 7
    assert restored.metadata == %{"lang" => "zh"}
    assert restored.history == snapshot.history

    assert_receive {:session_event, restored_event}, 300
    assert restored_event.type == "lifecycle.session_restored"
    assert restored_event.turn_id == 7
    assert restored_event.error == nil

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
    assert error_event.error.code == :rate_limited
    assert error_event.error.retriable == true
    assert error_event.error.retry_after == 2
  end

  test "rate_limited 未提供 retry_after 时默认 1 秒" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-rate-limit-default",
        backend: fn _message, _opts, _ctx ->
          {:error, {:rate_limited, nil, %{provider: "mock"}}}
        end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "trigger", [])

    events = receive_until_turn_completed([])
    error_event = Enum.find(events, &(&1.type == "error.runtime"))

    assert error_event != nil
    assert error_event.error.code == :rate_limited
    assert error_event.error.retriable == true
    assert error_event.error.retry_after == 1
  end

  test "retriable 严格按 code 映射，不接受显式字段覆盖" do
    rate_limited_error =
      Session.normalize_error(%{
        code: :rate_limited,
        message: "rate limited",
        retriable: false,
        details: %{}
      })

    invalid_argument_error =
      Session.normalize_error(%{
        code: :invalid_argument,
        message: "invalid argument",
        retriable: true,
        details: %{}
      })

    assert rate_limited_error.retriable == true
    assert invalid_argument_error.retriable == false
  end

  test "session API 在失效 pid 场景返回统一错误而非抛 exit" do
    {:ok, session} = Session.start_link(session_id: "session-dead-pid")
    assert :ok = Session.close(session)

    assert {:error, history_error} = Session.history(session)
    assert history_error.code == :session_not_found

    assert {:error, prompt_error} = Session.prompt(session, "hello", [])
    assert prompt_error.code == :session_not_found

    assert {:error, restore_error} = Session.restore(session, %{})
    assert restore_error.code == :session_not_found
  end

  test "并发 prompt 下 Session 保持可用且完成所有 turn" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-concurrent",
        backend: fn message, _opts, _ctx ->
          Process.sleep(10)
          {:ok, [{:chunk, "echo:" <> message}, :done]}
        end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    tasks =
      for i <- 1..8 do
        Task.async(fn -> Session.prompt(session, "m#{i}", []) end)
      end

    assert Enum.all?(tasks, &(Task.await(&1, 1_000) == :ok))

    events = receive_until_turn_completed_count([], 8)
    completed = Enum.filter(events, &(&1.type == "lifecycle.turn_completed"))

    assert length(completed) == 8
    assert MapSet.size(MapSet.new(Enum.map(completed, & &1.turn_id))) == 8
    assert wait_until(fn -> history_len_at_least?(session, 16) end)
    assert Process.alive?(session)
  end

  test "错误详情会执行深度限制，避免无限递归展开" do
    deep_details =
      Enum.reduce(1..20, %{}, fn idx, acc ->
        %{"level_#{idx}" => acc}
      end)

    error =
      Session.normalize_error(%{code: :internal_error, message: "boom", details: deep_details})

    assert error.code == :internal_error
    assert contains_truncated_marker?(error.details)
    assert max_depth(error.details) <= 8
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

  defp receive_until_turn_completed_count(acc, target_count) do
    completed_count =
      Enum.count(acc, fn event -> event.type == "lifecycle.turn_completed" end)

    if completed_count >= target_count do
      acc
    else
      receive do
        {:session_event, event} ->
          receive_until_turn_completed_count(acc ++ [event], target_count)
      after
        2_000 ->
          flunk("等待并发 turn 完成事件超时")
      end
    end
  end

  defp history_len_at_least?(session, min_len) do
    case Session.history(session) do
      {:ok, history} -> length(history) >= min_len
      {:error, _} -> false
    end
  end

  defp contains_truncated_marker?(value) when is_map(value) do
    Map.get(value, :truncated) == true or
      Enum.any?(value, fn {_k, v} -> contains_truncated_marker?(v) end)
  end

  defp contains_truncated_marker?(value) when is_list(value) do
    Enum.any?(value, &contains_truncated_marker?/1)
  end

  defp contains_truncated_marker?("[truncated]"), do: true
  defp contains_truncated_marker?(_), do: false

  defp max_depth(value) when is_map(value) do
    if map_size(value) == 0 do
      1
    else
      1 + Enum.max(Enum.map(Map.values(value), &max_depth/1))
    end
  end

  defp max_depth(value) when is_list(value) do
    if value == [] do
      1
    else
      1 + Enum.max(Enum.map(value, &max_depth/1))
    end
  end

  defp max_depth(_), do: 0

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
