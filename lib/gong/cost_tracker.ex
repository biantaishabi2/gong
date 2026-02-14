defmodule Gong.CostTracker do
  @moduledoc """
  Cost/Token 追踪 — 每次 LLM 调用统计 token、cost、cache hit。

  基于进程字典，零 GenServer 开销。
  """

  @type usage :: %{
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          cache_hit_tokens: non_neg_integer(),
          total_cost: float()
        }

  @type call_record :: %{
          model: String.t(),
          usage: usage(),
          timestamp: integer()
        }

  @key :gong_cost_tracker

  @doc "初始化追踪器（清空历史）"
  @spec init() :: :ok
  def init do
    Process.put(@key, [])
    :ok
  end

  @doc "记录一次 LLM 调用"
  @spec record(String.t(), usage()) :: :ok
  def record(model, usage) when is_binary(model) and is_map(usage) do
    record = %{
      model: model,
      usage: normalize_usage(usage),
      timestamp: System.monotonic_time(:millisecond)
    }

    history = Process.get(@key, [])
    Process.put(@key, [record | history])
    :ok
  end

  @doc "获取累计统计"
  @spec summary() :: %{
          total_input: non_neg_integer(),
          total_output: non_neg_integer(),
          total_cache_hit: non_neg_integer(),
          total_cost: float(),
          call_count: non_neg_integer()
        }
  def summary do
    history = Process.get(@key, [])

    history
    |> Enum.reduce(
      %{total_input: 0, total_output: 0, total_cache_hit: 0, total_cost: 0.0, call_count: 0},
      fn record, acc ->
        %{
          total_input: acc.total_input + record.usage.input_tokens,
          total_output: acc.total_output + record.usage.output_tokens,
          total_cache_hit: acc.total_cache_hit + record.usage.cache_hit_tokens,
          total_cost: acc.total_cost + record.usage.total_cost,
          call_count: acc.call_count + 1
        }
      end
    )
  end

  @doc "获取最近一次调用记录"
  @spec last_call() :: call_record() | nil
  def last_call do
    case Process.get(@key, []) do
      [latest | _] -> latest
      [] -> nil
    end
  end

  @doc "获取调用历史"
  @spec history() :: [call_record()]
  def history do
    Process.get(@key, []) |> Enum.reverse()
  end

  @doc "记录流中断时的部分令牌（带 :partial 标记）"
  @spec record_partial(String.t(), non_neg_integer(), non_neg_integer()) :: :ok
  def record_partial(model, input_tokens, output_tokens) when is_binary(model) do
    record = %{
      model: model,
      usage: %{
        input_tokens: input_tokens,
        output_tokens: output_tokens,
        cache_hit_tokens: 0,
        total_cost: 0.0
      },
      timestamp: System.monotonic_time(:millisecond),
      partial: true
    }

    history = Process.get(@key, [])
    Process.put(@key, [record | history])
    :ok
  end

  @doc "清空追踪数据"
  @spec reset() :: :ok
  def reset do
    Process.put(@key, [])
    :ok
  end

  defp normalize_usage(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      cache_hit_tokens: Map.get(usage, :cache_hit_tokens, 0),
      total_cost: Map.get(usage, :total_cost, 0.0)
    }
  end
end
