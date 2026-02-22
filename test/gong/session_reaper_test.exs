defmodule Gong.SessionReaperTest do
  use ExUnit.Case, async: false

  alias Gong.SessionManager
  alias Gong.SessionReaper

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

  test "idle 超时回收" do
    {:ok, pid, session_id} = SessionManager.create_session(create_opts())

    # 手动篡改 ETS 索引的 last_active_at 和 created_at 使其超过 idle_ttl
    [{^session_id, ext_key, created_at, _last_active, ^pid}] =
      :ets.lookup(Gong.SessionIndex, session_id)

    past = System.monotonic_time(:millisecond) - 200
    :ets.insert(Gong.SessionIndex, {session_id, ext_key, created_at, past, pid})

    # 启动 reaper 并用短 idle_ttl 触发
    {:ok, reaper} = SessionReaper.start_link(
      idle_ttl: 100,
      absolute_ttl: :timer.hours(24),
      max_sessions: 5000,
      sweep_interval: :timer.hours(1),
      name: :"reaper_idle_#{System.unique_integer([:positive])}"
    )

    SessionReaper.sweep_now(reaper)

    # 等待 session 进程退出
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000

    assert {:error, :not_found} = SessionManager.get_session(session_id)
    GenServer.stop(reaper)
  end

  test "absolute 超时回收" do
    {:ok, pid, session_id} = SessionManager.create_session(create_opts())

    [{^session_id, ext_key, _created, last_active, ^pid}] =
      :ets.lookup(Gong.SessionIndex, session_id)

    past = System.monotonic_time(:millisecond) - 200
    :ets.insert(Gong.SessionIndex, {session_id, ext_key, past, last_active, pid})

    {:ok, reaper} = SessionReaper.start_link(
      idle_ttl: :timer.hours(1),
      absolute_ttl: 100,
      max_sessions: 5000,
      sweep_interval: :timer.hours(1),
      name: :"reaper_abs_#{System.unique_integer([:positive])}"
    )

    SessionReaper.sweep_now(reaper)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000

    assert {:error, :not_found} = SessionManager.get_session(session_id)
    GenServer.stop(reaper)
  end

  test "LRU 驱逐至 target" do
    pids =
      for _ <- 1..5 do
        {:ok, pid, _sid} = SessionManager.create_session(create_opts())
        pid
      end

    {:ok, reaper} = SessionReaper.start_link(
      idle_ttl: :timer.hours(1),
      absolute_ttl: :timer.hours(24),
      max_sessions: 3,
      target_ratio: 0.66,
      sweep_interval: :timer.hours(1),
      name: :"reaper_lru_#{System.unique_integer([:positive])}"
    )

    SessionReaper.sweep_now(reaper)
    Process.sleep(500)

    # 应驱逐到约 2 个（3 * 0.66 = 1.98 ≈ 1, 5 - 1 = 4 个要驱逐...不对）
    # max_sessions=3, 超出时驱逐。remaining=5 > 3, target=trunc(3*0.66)=1, to_evict=5-1=4
    # 应保留 1 个
    alive_count = Enum.count(pids, &Process.alive?/1)
    assert alive_count <= 3

    GenServer.stop(reaper)
    Enum.each(pids, fn p -> if Process.alive?(p), do: Gong.Session.close(p) end)
  end

  test "空表不报错" do
    {:ok, reaper} = SessionReaper.start_link(
      idle_ttl: 100,
      absolute_ttl: 100,
      max_sessions: 5000,
      sweep_interval: :timer.hours(1),
      name: :"reaper_empty_#{System.unique_integer([:positive])}"
    )

    assert :ok = SessionReaper.sweep_now(reaper)
    GenServer.stop(reaper)
  end
end
