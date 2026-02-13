defmodule Gong.Abort do
  @moduledoc """
  Abort 信号管理 — 基于进程字典，零 GenServer 开销。

  在关键检查点调用 check!/0 来检查是否应中止操作。
  """

  @abort_key :gong_abort
  @abort_reason_key :gong_abort_reason

  @doc "发送 abort 信号"
  @spec signal!(term()) :: :ok
  def signal!(reason \\ :user) do
    Process.put(@abort_key, true)
    Process.put(@abort_reason_key, reason)
    :ok
  end

  @doc "检查 abort 信号，如果已设置则 throw"
  @spec check!() :: :ok
  def check! do
    if Process.get(@abort_key, false) do
      reason = Process.get(@abort_reason_key, :user)
      throw {:aborted, reason}
    end

    :ok
  end

  @doc "重置 abort 信号"
  @spec reset!() :: :ok
  def reset! do
    Process.delete(@abort_key)
    Process.delete(@abort_reason_key)
    :ok
  end

  @doc "查询是否已设置 abort 信号"
  @spec aborted?() :: boolean()
  def aborted? do
    Process.get(@abort_key, false)
  end

  @doc "获取 abort 原因"
  @spec reason() :: term() | nil
  def reason do
    if aborted?() do
      Process.get(@abort_reason_key, :user)
    else
      nil
    end
  end

  @doc "安全执行函数，捕获 abort throw"
  @spec safe_execute(fun()) :: {:ok, term()} | {:aborted, term()}
  def safe_execute(fun) do
    try do
      result = fun.()
      {:ok, result}
    catch
      {:aborted, reason} ->
        {:aborted, reason}
    end
  end
end
