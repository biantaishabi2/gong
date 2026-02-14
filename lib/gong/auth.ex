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

  # ── 认证锁文件管理 ──

  @doc "写入认证锁文件（JSON 格式）"
  @spec write_lock_file(Path.t(), map()) :: :ok | {:error, term()}
  def write_lock_file(path, data) when is_map(data) do
    content = Jason.encode!(data)
    File.mkdir_p!(Path.dirname(path))
    File.write(path, content)
  end

  @doc "读取认证锁文件"
  @spec read_lock_file(Path.t()) :: {:ok, map()} | {:error, term()}
  def read_lock_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "恢复损坏的锁文件：删除并返回默认值"
  @spec recover_lock_file(Path.t()) :: {:ok, map()}
  def recover_lock_file(path) do
    case read_lock_file(path) do
      {:ok, data} ->
        {:ok, data}

      {:error, _} ->
        File.rm(path)
        {:ok, %{"token" => nil, "recovered" => true}}
    end
  end

  @doc "登出：清除认证状态并清理模型引用"
  @spec logout() :: :ok
  def logout do
    # 清除进程中的认证状态
    Process.delete(:gong_auth_token)
    # 清理模型注册表中的 auth 引用
    Gong.ModelRegistry.clear_auth_references()
    :ok
  end

  @doc "检测 token 剩余有效期，低于阈值时自动刷新"
  @spec check_and_refresh(token(), integer()) :: {:ok, token()} | {:unchanged, token()}
  def check_and_refresh(token, threshold_seconds \\ 300) do
    case token do
      %{expires_at: nil} ->
        {:unchanged, token}

      %{expires_at: expires_at} ->
        remaining = expires_at - System.os_time(:second)

        if remaining < threshold_seconds do
          # 模拟刷新
          new_token = %{
            access_token: "refreshed_#{System.unique_integer([:positive])}",
            refresh_token: token[:refresh_token] || token["refresh_token"],
            expires_at: System.os_time(:second) + 3600
          }
          {:ok, new_token}
        else
          {:unchanged, token}
        end
    end
  end
end
