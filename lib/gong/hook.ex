defmodule Gong.Hook do
  @moduledoc """
  Hook 行为定义。

  提供 6 个可选回调，分为拦截型和变换型：

  ## 拦截型
  - `before_tool_call/2` — 工具执行前拦截，返回 :ok 放行或 {:block, reason} 阻止
  - `before_session_op/2` — 会话操作前拦截，返回 :ok 放行或 :cancel 取消

  ## 变换型
  - `on_tool_result/2` — 变换工具执行结果
  - `on_context/1` — 变换上下文消息列表
  - `on_input/2` — 变换用户输入
  - `on_before_agent/2` — Agent 调用前注入/变换
  """

  # 拦截型回调
  @callback before_tool_call(tool :: atom(), params :: map()) ::
              :ok | {:block, String.t()}

  @callback before_session_op(op :: atom(), meta :: map()) ::
              :ok | :cancel

  # 变换型回调
  @callback on_tool_result(tool :: atom(), result :: map()) :: map()

  @callback on_context(messages :: [map()]) :: [map()]

  @callback on_input(text :: String.t(), images :: [map()]) ::
              {:transform, String.t(), [map()]} | :passthrough | :handled

  @callback on_before_agent(prompt :: String.t(), system :: String.t()) ::
              {String.t(), String.t(), [map()]}

  @optional_callbacks [
    before_tool_call: 2,
    before_session_op: 2,
    on_tool_result: 2,
    on_context: 1,
    on_input: 2,
    on_before_agent: 2
  ]
end
