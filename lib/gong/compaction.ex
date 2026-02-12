defmodule Gong.Compaction do
  @moduledoc """
  上下文压缩模块。

  当会话历史超过 token 预算时，对旧消息进行压缩：
  - 滑动窗口保留最近 N 条消息完整内容
  - 窗口外的消息由 LLM 生成摘要替代
  - 系统消息和 anchor 消息始终保留
  """

  @default_window_size 20
  @default_max_tokens 100_000

  @doc "压缩消息列表，返回压缩后的消息和摘要"
  @spec compact([map()], keyword()) :: {[map()], String.t() | nil}
  def compact(messages, opts \\ []) do
    window = Keyword.get(opts, :window_size, @default_window_size)
    _max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    if length(messages) <= window do
      {messages, nil}
    else
      # TODO: 实现压缩逻辑
      {messages, nil}
    end
  end
end
