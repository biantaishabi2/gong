defmodule Gong.HeaderProfile do
  @moduledoc """
  请求头策略层。

  根据 profile 原子返回预定义的 headers map，
  作为 LLMRouter 合并链中的最低优先级基底。
  """

  @type profile :: :default | :opencode

  @doc """
  根据 profile 返回对应的 headers map。

  - `:default` — 不注入额外头，返回空 map
  - `:opencode` — 注入最小稳定指纹头集合
  - 未知 profile — 静默回退到 `:default`
  """
  @spec resolve(profile()) :: map()
  def resolve(:default), do: %{}

  def resolve(:opencode) do
    %{
      "User-Agent" => "OpenCode/1.0",
      "X-Client-Name" => "opencode",
      "Accept" => "application/json"
    }
  end

  def resolve(_unknown), do: resolve(:default)
end
