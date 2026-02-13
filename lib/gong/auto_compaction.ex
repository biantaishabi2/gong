defmodule Gong.AutoCompaction do
  @moduledoc """
  Agent 循环自动压缩。

  每轮对话结束后检查上下文 token 数是否超过预算，
  超过则自动触发 Compaction.compact/2。
  与 Steering 配合确保压缩期间排队的消息不丢失。
  """

  @default_context_window 128_000
  @default_reserve_tokens 16_384

  @doc "检查消息列表是否超过 token 预算"
  @spec should_compact?([map()], keyword()) :: boolean()
  def should_compact?(messages, opts \\ []) do
    context_window = Keyword.get(opts, :context_window, @default_context_window)
    reserve_tokens = Keyword.get(opts, :reserve_tokens, @default_reserve_tokens)
    threshold = context_window - reserve_tokens

    token_count = Gong.Compaction.TokenEstimator.estimate_messages(messages)
    token_count > threshold
  end

  @doc """
  自动压缩入口。

  - 未超阈值 → {:no_action, messages}
  - 超阈值且获取锁成功 → {:compacted, compacted_messages, summary}
  - 超阈值但锁被占用 → {:skipped, :lock_busy}
  """
  @spec auto_compact([map()], keyword()) ::
          {:no_action, [map()]}
          | {:compacted, [map()], String.t() | nil}
          | {:skipped, :lock_busy}
  def auto_compact(messages, opts \\ []) do
    if should_compact?(messages, opts) do
      session_id = Keyword.get(opts, :session_id, "auto_compact")

      case Gong.Compaction.Lock.acquire(session_id) do
        :ok ->
          try do
            {compacted, summary} = Gong.Compaction.compact(messages, opts)
            {:compacted, compacted, summary}
          after
            Gong.Compaction.Lock.release(session_id)
          end

        {:error, _} ->
          {:skipped, :lock_busy}
      end
    else
      {:no_action, messages}
    end
  end
end
