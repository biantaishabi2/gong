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

    # 注册 DeepSeek provider（复用 OpenAI ChatAPI）
    ReqLLM.Providers.register(Gong.Providers.DeepSeek)

    # 初始化 ETS 表（非 GenServer，启动时创建即可）
    Gong.CommandRegistry.init()
    Gong.PromptTemplate.init()
    Gong.ModelRegistry.init()

    # 注册 Kimi/MiniMax/GLM 模型配置
    Gong.ModelRegistry.register(:kimi, %{
      provider: "kimi",
      model_id: "moonshot-v1-auto",
      base_url: "https://api.moonshot.cn",
      api_key_env: "KIMI_API_KEY",
      auth_mode: :anthropic_header
    })

    Gong.ModelRegistry.register(:minimax, %{
      provider: "minimax",
      model_id: "minimax-text-01",
      base_url: "https://api.minimax.chat",
      api_key_env: "MINIMAX_API_KEY",
      auth_mode: :anthropic_header
    })

    Gong.ModelRegistry.register(:glm, %{
      provider: "glm",
      model_id: "glm-4",
      base_url: "https://open.bigmodel.cn/api/paas/v4",
      api_key_env: "GLM_API_KEY",
      auth_mode: :bearer
    })

    # 初始化 Provider 注册表并注册 DeepSeek
    Gong.ProviderRegistry.init()

    Gong.ProviderRegistry.register(
      "deepseek",
      Gong.Providers.DeepSeek,
      %{},
      priority: 10,
      timeout: 60_000
    )

    opts = [strategy: :one_for_one, name: Gong.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
