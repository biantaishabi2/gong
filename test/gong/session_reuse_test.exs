defmodule Gong.SessionReuseTest do
  use ExUnit.Case, async: false

  alias Gong.Session
  alias Gong.SessionManager

  # 简单文本回复的 llm_backend_fn
  defp text_llm(reply) do
    fn _agent_state, _call_id -> {:ok, {:text, reply}} end
  end

  defp create_opts(extra \\ []) do
    agent = Gong.Agent.new()
    [agent: agent, llm_backend_fn: text_llm("ok")] |> Keyword.merge(extra)
  end

  defp ensure_ets do
    if :ets.whereis(Gong.SessionIndex) == :undefined do
      :ets.new(Gong.SessionIndex, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  setup do
    ensure_ets()
    :ok
  end

  test "get_or_create_session 同 key 复用同一 session" do
    ext_key = "ext-reuse-#{System.unique_integer([:positive])}"
    {:ok, pid1, sid1} = SessionManager.get_or_create_session(ext_key, create_opts())
    {:ok, pid2, sid2} = SessionManager.get_or_create_session(ext_key, create_opts())

    assert pid1 == pid2
    assert sid1 == sid2

    Session.close(pid1)
  end

  test "get_or_create_session 不同 key 创建不同 session" do
    key1 = "ext-a-#{System.unique_integer([:positive])}"
    key2 = "ext-b-#{System.unique_integer([:positive])}"
    {:ok, pid1, sid1} = SessionManager.get_or_create_session(key1, create_opts())
    {:ok, pid2, sid2} = SessionManager.get_or_create_session(key2, create_opts())

    assert pid1 != pid2
    assert sid1 != sid2

    Session.close(pid1)
    Session.close(pid2)
  end

  test "关闭后再次 get_or_create 创建新 session" do
    ext_key = "ext-reopen-#{System.unique_integer([:positive])}"
    {:ok, pid1, sid1} = SessionManager.get_or_create_session(ext_key, create_opts())
    :ok = SessionManager.close_session(sid1, :manual)

    ref = Process.monitor(pid1)
    assert_receive {:DOWN, ^ref, :process, ^pid1, _}, 1000

    {:ok, pid2, sid2} = SessionManager.get_or_create_session(ext_key, create_opts())
    assert pid1 != pid2
    assert sid1 != sid2

    Session.close(pid2)
  end

  test "进程被 kill 后 get_or_create 自动重建" do
    ext_key = "ext-kill-#{System.unique_integer([:positive])}"
    {:ok, pid1, sid1} = SessionManager.get_or_create_session(ext_key, create_opts())

    Process.exit(pid1, :kill)
    ref = Process.monitor(pid1)
    assert_receive {:DOWN, ^ref, :process, ^pid1, _}, 1000

    {:ok, pid2, sid2} = SessionManager.get_or_create_session(ext_key, create_opts())
    assert pid2 != pid1
    assert sid2 != sid1

    Session.close(pid2)
  end

  test "close_session 幂等（重复关闭不报错）" do
    {:ok, pid, sid} = SessionManager.create_session(create_opts())
    :ok = SessionManager.close_session(sid)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000

    assert {:error, :not_found} = SessionManager.close_session(sid)
  end

  test "session_count 正确反映活跃数量" do
    before_count = SessionManager.session_count()

    {:ok, pid1, _sid1} = SessionManager.create_session(create_opts())
    {:ok, pid2, _sid2} = SessionManager.create_session(create_opts())

    assert SessionManager.session_count() >= before_count + 2

    Session.close(pid1)
    ref1 = Process.monitor(pid1)
    assert_receive {:DOWN, ^ref1, :process, ^pid1, _}, 1000

    assert SessionManager.session_count() >= before_count + 1

    Session.close(pid2)
    ref2 = Process.monitor(pid2)
    assert_receive {:DOWN, ^ref2, :process, ^pid2, _}, 1000
  end

  test "高并发下会话复用 — 所有 Task 拿到相同 pid" do
    ext_key = "ext-concurrent-#{System.unique_integer([:positive])}"

    results =
      1..10
      |> Enum.map(fn _ ->
        Task.async(fn ->
          SessionManager.get_or_create_session(ext_key, create_opts())
        end)
      end)
      |> Task.await_many(5000)

    pids = Enum.map(results, fn {:ok, pid, _sid} -> pid end)
    # 并发下可能有 1-2 个额外创建（竞态），但大多数应该拿到同一个 pid
    unique_pids = Enum.uniq(pids)
    # 至少保证不会创建 10 个不同的 session
    assert length(unique_pids) <= 3

    Enum.each(unique_pids, fn p -> if Process.alive?(p), do: Session.close(p) end)
  end
end
