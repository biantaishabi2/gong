defmodule Gong.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Jido AgentServer 依赖的注册表
      {Registry, keys: :unique, name: Jido.Registry},
      # Agent 会话注册表
      {Registry, keys: :unique, name: Gong.SessionRegistry},
      # Agent 会话动态监督器
      {DynamicSupervisor, name: Gong.SessionSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: Gong.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
