defmodule Gong.Steering do
  @moduledoc """
  Steering 消息队列管理。

  工具执行间隙检查 steering 消息，若有则跳过剩余工具调用。
  纯函数实现，GenServer 层通过 cast 入队、receive 出队。
  """

  @type message_type :: :steering | :follow_up
  @type message :: String.t() | {message_type(), String.t()}
  @type queue :: [message()]

  @doc "创建空队列"
  @spec new() :: queue()
  def new, do: []

  @doc "入队一条消息（字符串或 {type, content} 元组）"
  @spec push(queue(), message()) :: queue()
  def push(queue, message), do: queue ++ [message]

  @doc "出队一条 steering 消息（只出 :steering 类型或普通字符串），返回 {message | nil, 剩余队列}"
  @spec check(queue()) :: {String.t() | nil, queue()}
  def check([]), do: {nil, []}
  def check(queue) do
    case Enum.split_while(queue, fn
      {:follow_up, _} -> true
      _ -> false
    end) do
      {skipped, []} -> {nil, skipped}
      {skipped, [msg | rest]} ->
        content = case msg do
          {:steering, c} -> c
          c when is_binary(c) -> c
        end
        {content, skipped ++ rest}
    end
  end

  @doc "出队一条 follow_up 消息，返回 {message | nil, 剩余队列}"
  @spec check_follow_up(queue()) :: {String.t() | nil, queue()}
  def check_follow_up([]), do: {nil, []}
  def check_follow_up(queue) do
    case Enum.split_while(queue, fn
      {:follow_up, _} -> false
      _ -> true
    end) do
      {skipped, []} -> {nil, skipped}
      {skipped, [{:follow_up, content} | rest]} ->
        {content, skipped ++ rest}
    end
  end

  @doc "检查是否有待处理的 steering 消息（不含 follow_up）"
  @spec check_steering(queue()) :: {String.t() | nil, queue()}
  def check_steering(queue), do: check(queue)

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
