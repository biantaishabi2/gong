defmodule Gong.SessionTokenStatsTest do
  use ExUnit.Case, async: false

  alias Gong.Session

  # ── Helper: 创建带 usage 的 llm_backend_fn ──

  # 返回固定 text 响应，通过进程字典注入 usage
  defp text_llm_with_usage(reply, input_tokens, output_tokens) do
    fn _agent_state, _call_id ->
      # 通过进程字典累加 usage（模拟 build_llm_backend 的行为）
      current = Process.get(:gong_turn_usage, %{input_tokens: 0, output_tokens: 0})

      updated = %{
        input_tokens: current.input_tokens + input_tokens,
        output_tokens: current.output_tokens + output_tokens
      }

      Process.put(:gong_turn_usage, updated)
      {:ok, {:text, reply}}
    end
  end

  # 返回固定 text 响应，不注入 usage（测试回退行为）
  defp text_llm_no_usage(reply) do
    fn _agent_state, _call_id -> {:ok, {:text, reply}} end
  end

  # 多次调用的 llm_backend_fn（工具调用场景）
  defp tool_then_text_llm(tool_calls, final_reply, usages) do
    {:ok, queue_pid} = Agent.start_link(fn -> usages end)

    fn _agent_state, _call_id ->
      {usage, remaining} =
        Agent.get_and_update(queue_pid, fn
          [head | tail] -> {{head, tail}, tail}
          [] -> {{%{input_tokens: 0, output_tokens: 0}, []}, []}
        end)

      # 累加 usage
      current = Process.get(:gong_turn_usage, %{input_tokens: 0, output_tokens: 0})

      updated = %{
        input_tokens: current.input_tokens + usage.input_tokens,
        output_tokens: current.output_tokens + usage.output_tokens
      }

      Process.put(:gong_turn_usage, updated)

      if remaining != [] do
        {:ok, {:tool_calls, tool_calls}}
      else
        {:ok, {:text, final_reply}}
      end
    end
  end

  defp setup_agent_session(session_id, llm_fn, extra_opts \\ []) do
    agent = Gong.Agent.new()

    opts =
      [session_id: session_id, agent: agent, llm_backend_fn: llm_fn]
      |> Keyword.merge(extra_opts)

    Session.start_link(opts)
  end

  defp receive_until_turn_completed(acc) do
    receive do
      {:session_event, %{type: "lifecycle.turn_completed"} = event} ->
        Enum.reverse([event | acc])

      {:session_event, event} ->
        receive_until_turn_completed([event | acc])
    after
      3000 ->
        Enum.reverse(acc)
    end
  end

  # ── 测试场景 ──

  test "单轮对话 stats: usage 正确累计" do
    {:ok, session} =
      setup_agent_session("stats-single", text_llm_with_usage("hello", 150, 80))

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "hi", [])

    _events = receive_until_turn_completed([])

    {:ok, stats} = Session.stats(session)
    assert stats.total_turns == 1
    assert stats.total_input_tokens == 150
    assert stats.total_output_tokens == 80
    assert stats.total_cost > 0.0
  end

  test "多轮累计: 3 轮 stats 递增" do
    # 使用 Agent 管理多轮不同 usage
    usages = [
      {100, 50},
      {200, 80},
      {150, 70}
    ]

    {:ok, usage_pid} = Agent.start_link(fn -> usages end)

    llm_fn = fn _agent_state, _call_id ->
      {input, output} =
        Agent.get_and_update(usage_pid, fn
          [head | tail] -> {head, tail}
          [] -> {{0, 0}, []}
        end)

      current = Process.get(:gong_turn_usage, %{input_tokens: 0, output_tokens: 0})

      Process.put(:gong_turn_usage, %{
        input_tokens: current.input_tokens + input,
        output_tokens: current.output_tokens + output
      })

      {:ok, {:text, "reply"}}
    end

    {:ok, session} = setup_agent_session("stats-multi", llm_fn)
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    # 轮 1
    assert :ok = Session.prompt(session, "msg1", [])
    _events1 = receive_until_turn_completed([])

    # 轮 2
    assert :ok = Session.prompt(session, "msg2", [])
    _events2 = receive_until_turn_completed([])

    # 轮 3
    assert :ok = Session.prompt(session, "msg3", [])
    _events3 = receive_until_turn_completed([])

    {:ok, stats} = Session.stats(session)
    assert stats.total_turns == 3
    assert stats.total_input_tokens == 100 + 200 + 150
    assert stats.total_output_tokens == 50 + 80 + 70
    assert stats.total_cost > 0.0

    Agent.stop(usage_pid)
  end

  test "usage 缺失回退: 无 usage 时 token 计数为零" do
    {:ok, session} =
      setup_agent_session("stats-no-usage", text_llm_no_usage("hello"))

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "test", [])

    _events = receive_until_turn_completed([])

    {:ok, stats} = Session.stats(session)
    assert stats.total_turns == 1
    assert stats.total_input_tokens == 0
    assert stats.total_output_tokens == 0
    assert stats.total_cost == 0.0
  end

  test "turn_completed 事件包含 usage 字段" do
    {:ok, session} =
      setup_agent_session("stats-event", text_llm_with_usage("ok", 120, 60))

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "check", [])

    events = receive_until_turn_completed([])
    turn_completed = List.last(events)

    assert turn_completed.type == "lifecycle.turn_completed"
    assert turn_completed.payload[:usage] != nil
    usage = turn_completed.payload[:usage]
    assert usage.input_tokens == 120
    assert usage.output_tokens == 60
  end

  test "工具调用轮多次 LLM 调用累加" do
    tool_calls = [%{id: "tc_1", name: "Ls", arguments: %{"path" => "."}}]

    usages = [
      %{input_tokens: 100, output_tokens: 30},
      %{input_tokens: 120, output_tokens: 50}
    ]

    llm_fn = tool_then_text_llm(tool_calls, "done", usages)

    {:ok, session} = setup_agent_session("stats-tool", llm_fn)
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "list files", [])

    _events = receive_until_turn_completed([])

    {:ok, stats} = Session.stats(session)
    assert stats.total_turns == 1
    assert stats.total_input_tokens == 220
    assert stats.total_output_tokens == 80
    assert stats.total_cost > 0.0
  end

  test "Session.stats/1 API 在无对话时返回初始值" do
    {:ok, session} =
      setup_agent_session("stats-empty", text_llm_no_usage("unused"))

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    {:ok, stats} = Session.stats(session)
    assert stats == %{total_turns: 0, total_input_tokens: 0, total_output_tokens: 0, total_cost: 0.0}
  end
end
