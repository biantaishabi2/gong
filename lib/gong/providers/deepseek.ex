defmodule Gong.Providers.DeepSeek do
  @moduledoc """
  DeepSeek provider — OpenAI 兼容接口，指向 DeepSeek endpoint。

  通过 `use ReqLLM.Provider` 自动获得默认的 prepare_request/parse_response 实现，
  使用 OpenAI 兼容的 chat/completions 接口。
  """

  use ReqLLM.Provider,
    id: :deepseek,
    default_base_url: "https://api.deepseek.com",
    default_env_key: "DEEPSEEK_API_KEY"

  @doc "满足 Gong.ProviderRegistry.register/4 调用契约"
  def validate_config(_config), do: :ok
end
