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
      {DynamicSupervisor, name: Gong.SessionSupervisor, strategy: :one_for_one},
      # Session TTL/LRU 回收器
      Gong.SessionReaper
    ]

    # 注册 DeepSeek provider（复用 OpenAI ChatAPI）
    ReqLLM.Providers.register(Gong.Providers.DeepSeek)

    # 初始化 ETS 表（非 GenServer，启动时创建即可）
    Gong.CommandRegistry.init()
    Gong.PromptTemplate.init()
    Gong.ModelRegistry.init()

    # 创建 Session 索引 ETS 表
    init_session_index()

    opts = [strategy: :one_for_one, name: Gong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp init_session_index do
    if :ets.whereis(Gong.SessionIndex) == :undefined do
      :ets.new(Gong.SessionIndex, [:set, :public, :named_table, read_concurrency: true])
    end
  end
end
