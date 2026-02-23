defmodule Gong.Providers.OpenaiCompatProvider do
  @moduledoc """
  OpenAI 兼容协议适配器 — 适用于所有兼容 OpenAI chat/completions 接口的厂商。

  通过 `use ReqLLM.Provider` 获得默认的 prepare_request/parse_response 实现。
  实际的 base_url 和 api_key 在 ProviderRegistry 注册时通过 config 传入，
  LLMRouter 的 `resolve_config/2` 在运行时覆盖。

  ## 使用方式

      # 通过 register_compat 注册厂商实例
      ProviderRegistry.register_compat(:openai_compat, "deepseek", %{
        base_url: "https://api.deepseek.com",
        api_key_env: "DEEPSEEK_API_KEY"
      })
  """

  use ReqLLM.Provider,
    id: :openai_compat,
    default_base_url: "https://api.openai.com",
    default_env_key: "OPENAI_API_KEY"

  @doc "校验 provider 配置，base_url 为必填字段"
  def validate_config(%{base_url: base_url}) when is_binary(base_url) and base_url != "", do: :ok
  def validate_config(%{base_url: _}), do: {:error, "base_url 不能为空"}
  def validate_config(_), do: {:error, "缺少必填字段 base_url"}
end
