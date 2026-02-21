defmodule Gong.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Gong.SessionManager

  # 简单文本回复的 llm_backend_fn
  defp text_llm(reply) do
    fn _agent_state, _call_id -> {:ok, {:text, reply}} end
  end

  defp create_opts(extra \\ []) do
    agent = Gong.Agent.new()
    [agent: agent, llm_backend_fn: text_llm("ok")] |> Keyword.merge(extra)
  end

  test "create → get → 返回同一 pid" do
    {:ok, pid, session_id} = SessionManager.create_session(create_opts())
    on_exit(fn -> if Process.alive?(pid), do: Gong.Session.close(pid) end)

    assert is_pid(pid)
    assert is_binary(session_id)
    assert {:ok, ^pid} = SessionManager.get_session(session_id)
  end

  test "get 不存在的 id → :not_found" do
    assert {:error, :not_found} = SessionManager.get_session("nonexistent-id-#{System.unique_integer()}")
  end

  test "create → close → get → :not_found" do
    {:ok, pid, session_id} = SessionManager.create_session(create_opts())

    assert Process.alive?(pid)
    assert :ok = SessionManager.close_session(session_id)

    # 等待进程退出
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000

    assert {:error, :not_found} = SessionManager.get_session(session_id)
  end

  test "list 返回所有活跃 session" do
    {:ok, pid1, id1} = SessionManager.create_session(create_opts())
    {:ok, pid2, id2} = SessionManager.create_session(create_opts())
    on_exit(fn ->
      if Process.alive?(pid1), do: Gong.Session.close(pid1)
      if Process.alive?(pid2), do: Gong.Session.close(pid2)
    end)

    sessions = SessionManager.list_sessions()
    assert id1 in sessions
    assert id2 in sessions
  end

  test "重复 session_id 创建 → 返回错误" do
    sid = "dup-test-#{System.unique_integer([:positive])}"
    {:ok, pid, ^sid} = SessionManager.create_session(create_opts(session_id: sid))
    on_exit(fn -> if Process.alive?(pid), do: Gong.Session.close(pid) end)

    assert {:error, {:already_exists, ^pid, ^sid}} = SessionManager.create_session(create_opts(session_id: sid))
  end

  test "close 不存在的 session → :not_found" do
    assert {:error, :not_found} = SessionManager.close_session("no-such-session-#{System.unique_integer()}")
  end
end
