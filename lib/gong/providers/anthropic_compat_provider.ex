defmodule Gong.Providers.AnthropicCompatProvider do
  @moduledoc """
  Anthropic 兼容协议适配器 — 适用于所有兼容 Anthropic Messages API 的厂商。

  基于 `use ReqLLM.Provider` 但覆写请求/响应处理以适配 Anthropic 消息格式：
  - system 作为顶层参数（非 message role）
  - messages 中不含 system role
  - 请求 headers 含 anthropic-version

  ## 使用方式

      ProviderRegistry.register_compat(:anthropic_compat, "anthropic", %{
        base_url: "https://api.anthropic.com",
        api_key_env: "ANTHROPIC_API_KEY"
      })
  """

  use ReqLLM.Provider,
    id: :anthropic_compat,
    default_base_url: "https://api.anthropic.com",
    default_env_key: "ANTHROPIC_API_KEY"

  @anthropic_version "2023-06-01"

  @doc "校验 provider 配置，base_url 为必填字段"
  def validate_config(%{base_url: base_url}) when is_binary(base_url) and base_url != "", do: :ok
  def validate_config(%{base_url: _}), do: {:error, "base_url 不能为空"}
  def validate_config(_), do: {:error, "缺少必填字段 base_url"}

  @doc "构建 Anthropic 格式的请求 payload"
  @spec build_payload([map()], String.t(), keyword()) :: map()
  def build_payload(messages, model, opts \\ []) do
    {system_messages, non_system} =
      Enum.split_with(messages, fn msg ->
        Map.get(msg, :role, Map.get(msg, "role")) == "system"
      end)

    # 合并所有 system 消息的 content
    system_text =
      system_messages
      |> Enum.map(fn msg -> Map.get(msg, :content, Map.get(msg, "content", "")) end)
      |> Enum.join("\n")

    payload = %{
      model: model,
      messages: non_system,
      max_tokens: Keyword.get(opts, :max_tokens, 4096)
    }

    if system_text != "" do
      Map.put(payload, :system, system_text)
    else
      payload
    end
  end

  @doc "返回 Anthropic API 所需的默认 headers"
  @spec default_headers() :: map()
  def default_headers do
    %{
      "anthropic-version" => @anthropic_version,
      "content-type" => "application/json"
    }
  end
end
