defmodule Gong.Providers.DeepSeek do
  @moduledoc """
  DeepSeek provider — OpenAI 兼容接口，指向 DeepSeek endpoint。

  **已弃用**：请使用 `Gong.Providers.OpenaiCompatProvider` 配合
  `ProviderRegistry.register_compat(:openai_compat, "deepseek", config)` 代替。

  本模块保留以维持编译兼容性，新代码不应直接引用此模块。
  迁移路径：通过 Application.start 中的 register_compat 注册 DeepSeek 为
  openai_compat 实例，旧名称 "deepseek" 通过 alias 自动映射。
  """

  @deprecated "使用 Gong.Providers.OpenaiCompatProvider + ProviderRegistry.register_compat/4 代替"

  use ReqLLM.Provider,
    id: :deepseek,
    default_base_url: "https://api.deepseek.com",
    default_env_key: "DEEPSEEK_API_KEY"

  @doc "满足 Gong.ProviderRegistry.register/4 调用契约"
  def validate_config(_config), do: :ok
end
