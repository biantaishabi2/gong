defmodule Gong.SessionReaper do
  @moduledoc """
  Session TTL/LRU 回收 GenServer。

  定期扫描 ETS 索引，按 idle_ttl / absolute_ttl 过期回收，
  超过 max_sessions 时按 LRU 驱逐至 target_ratio。
  """

  use GenServer

  require Logger

  @default_idle_ttl :timer.minutes(30)
  @default_absolute_ttl :timer.hours(24)
  @default_max_sessions 5000
  @default_target_ratio 0.9
  @default_sweep_interval :timer.seconds(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "立即执行一次 sweep（测试用）"
  @spec sweep_now(GenServer.server()) :: :ok
  def sweep_now(server \\ __MODULE__) do
    GenServer.call(server, :sweep_now)
  end

  @impl true
  def init(opts) do
    state = %{
      idle_ttl: Keyword.get(opts, :idle_ttl, @default_idle_ttl),
      absolute_ttl: Keyword.get(opts, :absolute_ttl, @default_absolute_ttl),
      max_sessions: Keyword.get(opts, :max_sessions, @default_max_sessions),
      target_ratio: Keyword.get(opts, :target_ratio, @default_target_ratio),
      sweep_interval: Keyword.get(opts, :sweep_interval, @default_sweep_interval)
    }

    schedule_sweep(state.sweep_interval)
    {:ok, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    do_sweep(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    do_sweep(state)
    schedule_sweep(state.sweep_interval)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_sweep(interval) do
    Process.send_after(self(), :sweep, interval)
  end

  defp do_sweep(state) do
    now = System.monotonic_time(:millisecond)

    entries =
      try do
        :ets.tab2list(Gong.SessionIndex)
      rescue
        ArgumentError -> []
      end

    # 第 1 步：按 TTL 筛选过期
    {expired, alive} =
      Enum.split_with(entries, fn {_sid, _key, created_at, last_active_at, _pid} ->
        idle_expired?(now, last_active_at, state.idle_ttl) or
          absolute_expired?(now, created_at, state.absolute_ttl)
      end)

    # 关闭 TTL 过期的 session
    Enum.each(expired, fn {session_id, _key, created_at, _last_active_at, _pid} ->
      reason =
        if absolute_expired?(now, created_at, state.absolute_ttl),
          do: :ttl_absolute_expired,
          else: :ttl_idle_expired

      close_session_safe(session_id, reason)
    end)

    # 第 2 步：LRU 驱逐（超出 max_sessions 时）
    remaining_count = length(alive)

    if remaining_count > state.max_sessions do
      target = trunc(state.max_sessions * state.target_ratio)
      to_evict = remaining_count - target

      if to_evict > 0 do
        # 按 last_active_at 升序排序，驱逐最不活跃的
        alive
        |> Enum.sort_by(fn {_sid, _key, _created, last_active_at, _pid} -> last_active_at end)
        |> Enum.take(to_evict)
        |> Enum.each(fn {session_id, _key, _created, _active, _pid} ->
          close_session_safe(session_id, :lru_evicted)
        end)
      end
    end
  end

  defp idle_expired?(now, last_active_at, idle_ttl) do
    now - last_active_at > idle_ttl
  end

  defp absolute_expired?(now, created_at, absolute_ttl) do
    now - created_at > absolute_ttl
  end

  defp close_session_safe(session_id, reason) do
    try do
      Gong.SessionManager.close_session(session_id, reason)
    rescue
      e ->
        Logger.warning("SessionReaper 关闭 session 失败: #{Exception.message(e)}",
          session_id: session_id,
          reason: reason
        )
    catch
      :exit, _ -> :ok
    end
  end
end
