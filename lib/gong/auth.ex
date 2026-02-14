defmodule Gong.Auth do
  @moduledoc """
  Provider 认证模块 — 支持 API Key 和 OAuth 两种认证方式。

  OAuth 流程：生成授权 URL → 用户授权 → 回调获取 token → 刷新 token。
  """

  @type auth_method :: :api_key | :oauth
  @type oauth_config :: %{
          client_id: String.t(),
          client_secret: String.t(),
          authorize_url: String.t(),
          token_url: String.t(),
          redirect_uri: String.t(),
          scopes: [String.t()]
        }

  @type token :: %{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_at: integer() | nil
        }

  @doc "检测 provider 的认证方式"
  @spec auth_method(String.t()) :: auth_method()
  def auth_method("anthropic"), do: :oauth
  def auth_method("google"), do: :oauth
  def auth_method("github_copilot"), do: :oauth
  def auth_method(_), do: :api_key

  @doc "生成 OAuth 授权 URL"
  @spec authorize_url(oauth_config(), String.t()) :: String.t()
  def authorize_url(config, state \\ "") do
    params = URI.encode_query(%{
      client_id: config.client_id,
      redirect_uri: config.redirect_uri,
      scope: Enum.join(config.scopes, " "),
      response_type: "code",
      state: state
    })

    "#{config.authorize_url}?#{params}"
  end

  @doc "用授权码交换 token（mock 实现）"
  @spec exchange_code(oauth_config(), String.t()) :: {:ok, token()} | {:error, String.t()}
  def exchange_code(_config, code) when is_binary(code) do
    # 实际实现需要 HTTP 请求
    {:ok, %{
      access_token: "mock_access_#{code}",
      refresh_token: "mock_refresh_#{code}",
      expires_at: System.os_time(:second) + 3600
    }}
  end

  @doc "刷新 token（mock 实现）"
  @spec refresh_token(oauth_config(), String.t()) :: {:ok, token()} | {:error, String.t()}
  def refresh_token(_config, refresh) when is_binary(refresh) do
    {:ok, %{
      access_token: "refreshed_access",
      refresh_token: refresh,
      expires_at: System.os_time(:second) + 3600
    }}
  end

  @doc "检查 token 是否过期"
  @spec token_expired?(token()) :: boolean()
  def token_expired?(%{expires_at: nil}), do: false
  def token_expired?(%{expires_at: expires_at}) do
    System.os_time(:second) >= expires_at
  end

  @doc "获取 provider 的 API Key"
  @spec get_api_key(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def get_api_key(env_var) when is_binary(env_var) do
    case System.get_env(env_var) do
      nil -> {:error, "环境变量 #{env_var} 未设置"}
      key -> {:ok, key}
    end
  end
end
