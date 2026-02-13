defmodule Gong.Steering do
  @moduledoc """
  Steering 消息队列管理。

  工具执行间隙检查 steering 消息，若有则跳过剩余工具调用。
  纯函数实现，GenServer 层通过 cast 入队、receive 出队。
  """

  @type message :: String.t()
  @type queue :: [message()]

  @doc "创建空队列"
  @spec new() :: queue()
  def new, do: []

  @doc "入队一条 steering 消息"
  @spec push(queue(), message()) :: queue()
  def push(queue, message), do: queue ++ [message]

  @doc "出队一条 steering 消息，返回 {message | nil, 剩余队列}"
  @spec check(queue()) :: {message() | nil, queue()}
  def check([]), do: {nil, []}
  def check([msg | rest]), do: {msg, rest}

  @doc "是否有待处理的 steering 消息"
  @spec pending?(queue()) :: boolean()
  def pending?([]), do: false
  def pending?(_), do: true

  @doc "生成工具跳过结果（steering 中断时返回给 LLM）"
  @spec skip_result(String.t()) :: {:error, String.t()}
  def skip_result(tool_name) do
    {:error, "Skipped tool '#{tool_name}' due to queued user message"}
  end
end
