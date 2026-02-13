defmodule Gong.Compaction.Lock do
  @moduledoc """
  并发压缩锁，基于 ETS 实现。

  同一 session 同时只允许一次压缩操作。
  """

  @table __MODULE__

  @doc "确保 ETS 表已创建"
  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table])
        :ok

      _ ->
        :ok
    end
  end

  @doc "尝试获取压缩锁"
  @spec acquire(String.t()) :: :ok | {:error, :compaction_in_progress}
  def acquire(session_id) when is_binary(session_id) do
    ensure_table()

    case :ets.insert_new(@table, {session_id, self(), System.monotonic_time()}) do
      true -> :ok
      false -> {:error, :compaction_in_progress}
    end
  end

  @doc "释放压缩锁"
  @spec release(String.t()) :: :ok
  def release(session_id) when is_binary(session_id) do
    ensure_table()
    :ets.delete(@table, session_id)
    :ok
  end
end
