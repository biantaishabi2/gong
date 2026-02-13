defmodule Gong.Retry do
  @moduledoc """
  LLM 请求自动重试（指数退避）。

  错误分类：
  - :transient — 可重试（429、连接超时等）
  - :context_overflow — 需要压缩上下文而非重试
  - :permanent — 不可恢复（认证失败、无效请求等）
  """

  @max_retries 3
  @base_delay_ms 1000

  @type error_class :: :transient | :context_overflow | :permanent

  @doc "将错误分类为 transient / context_overflow / permanent"
  @spec classify_error(term()) :: error_class()
  def classify_error(error) do
    error_str = to_string(error)

    cond do
      rate_limit?(error_str) -> :transient
      connection_error?(error_str) -> :transient
      context_overflow?(error_str) -> :context_overflow
      true -> :permanent
    end
  end

  @doc "是否应该重试"
  @spec should_retry?(error_class(), non_neg_integer()) :: boolean()
  def should_retry?(:transient, attempt) when attempt < @max_retries, do: true
  def should_retry?(_, _), do: false

  @doc "计算第 N 次重试的延迟毫秒数（指数退避）"
  @spec delay_ms(non_neg_integer()) :: non_neg_integer()
  def delay_ms(attempt) do
    trunc(@base_delay_ms * :math.pow(2, attempt))
  end

  @doc "返回最大重试次数"
  @spec max_retries() :: non_neg_integer()
  def max_retries, do: @max_retries

  # ── 错误模式匹配 ──

  defp rate_limit?(str), do: str =~ ~r/429|rate.?limit/i
  defp connection_error?(str), do: str =~ ~r/connect|timeout|ECONNREFUSED|ETIMEDOUT/i

  defp context_overflow?(str) do
    str =~ ~r/too long|exceeds.*context|token.*exceed|maximum prompt|reduce.*length/i
  end
end
