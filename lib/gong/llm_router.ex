defmodule Gong.LLMRouter do
  @moduledoc """
  LLM 统一路由入口。

  收敛 AgentLoop 和 Compaction.Summarizer 两条独立的 ReqLLM 直连分支，
  按 runtime > model > provider > default 优先级合并配置，
  通过 ProviderRegistry 获取运行时策略后委托 ReqLLM 执行。
  """

  alias Gong.HeaderProfile
  alias Gong.ProviderRegistry

  @default_timeout 60_000

  @doc """
  流式文本生成 — AgentLoop 主调用路径。

  返回 `{:ok, stream_response}` 透传流给调用方，不做缓冲。
  失败时自动沿 fallback chain 降级重试。
  """
  @spec stream_text(map(), [map()], keyword()) :: {:ok, term()} | {:error, term()}
  def stream_text(model_config, messages, opts \\ []) do
    call_with_fallback(model_config, messages, opts, :stream_text)
  end

  @doc """
  非流式文本生成 — Compaction.Summarizer 主调用路径。

  返回 `{:ok, response}` 或 `{:error, reason}`。
  失败时自动沿 fallback chain 降级重试。
  """
  @spec generate_text(map(), [map()], keyword()) :: {:ok, term()} | {:error, term()}
  def generate_text(model_config, messages, opts \\ []) do
    call_with_fallback(model_config, messages, opts, :generate_text)
  end

  @doc "将底层错误格式化为用户可读文案"
  @spec humanize_error(term()) :: String.t()
  def humanize_error(%{message: message}) when is_binary(message) and message != "", do: message

  def humanize_error(%{response_body: body, status: status, reason: reason})
      when is_map(body) and is_integer(status) do
    detail = Map.get(body, :message) || Map.get(body, "message") || reason || "请求失败"
    "#{detail} (HTTP #{status})"
  end

  def humanize_error(%{reason: reason, status: status})
      when is_binary(reason) and is_integer(status) do
    "#{reason} (HTTP #{status})"
  end

  def humanize_error(error) when is_binary(error), do: error
  def humanize_error(error) when is_atom(error), do: to_string(error)
  def humanize_error(error), do: inspect(error)

  @doc """
  按 runtime > model > provider > default 优先级合并配置。

  返回包含 :model_str, :receive_timeout 等最终配置的 map。
  """
  @spec resolve_config(map(), keyword()) :: map()
  def resolve_config(model_config, runtime_opts \\ []) do
    provider_name = Map.get(model_config, :provider, "deepseek")

    # provider 级配置
    provider_config =
      case ProviderRegistry.resolve_provider_config(provider_name) do
        {:ok, config} -> config
        {:error, _} -> %{}
      end

    # provider 级 timeout
    provider_timeout = Map.get(provider_config, :timeout) || @default_timeout

    # model 级配置
    model_base_url = Map.get(model_config, :base_url)
    model_headers = Map.get(model_config, :headers, %{})

    # provider 级 base_url/headers
    provider_base_url = Map.get(provider_config, :base_url)
    provider_headers = Map.get(provider_config, :headers, %{})

    # runtime 级覆盖
    runtime_base_url = Keyword.get(runtime_opts, :base_url)
    runtime_timeout = Keyword.get(runtime_opts, :receive_timeout)
    runtime_headers = Keyword.get(runtime_opts, :headers)

    # 合并：runtime > model > provider > default
    final_base_url = runtime_base_url || model_base_url || provider_base_url
    final_timeout = runtime_timeout || provider_timeout || @default_timeout

    # profile 级 headers（最低优先级基底）
    header_profile = Map.get(model_config, :header_profile, :default)
    profile_headers = HeaderProfile.resolve(header_profile)

    # 合并：runtime > model > provider > profile
    final_headers =
      profile_headers
      |> Map.merge(provider_headers || %{})
      |> Map.merge(model_headers || %{})
      |> Map.merge(runtime_headers || %{})

    # auth_mode 鉴权头注入：仅当 model_config 显式声明 auth_mode 时才注入
    final_headers = inject_auth_header(final_headers, model_config)

    model_id = Map.get(model_config, :model_id, "deepseek-chat")
    model_str = "#{provider_name}:#{Map.get(model_config, :model_id, "deepseek-chat")}"
    req_provider = resolve_req_provider(provider_name, provider_config)

    req_model_spec =
      if req_provider do
        %{provider: req_provider, id: model_id}
      else
        nil
      end

    api_key_env = Map.get(model_config, :api_key_env) || Map.get(provider_config, :api_key_env)

    api_key =
      case api_key_env do
        env when is_binary(env) and env != "" -> System.get_env(env)
        _ -> nil
      end

    %{
      model_str: model_str,
      req_model_spec: req_model_spec,
      req_provider: req_provider,
      base_url: final_base_url,
      headers: final_headers,
      api_key: api_key,
      api_key_env: api_key_env,
      receive_timeout: final_timeout,
      provider_name: provider_name
    }
  end

  # ── 内部实现 ──

  defp call_with_fallback(model_config, messages, opts, method) do
    resolved = resolve_config(model_config, opts)
    provider_name = resolved.provider_name

    # 构建最终 opts：注入 timeout，保留原有 opts（如 tools）
    final_opts = build_final_opts(resolved, opts)

    model_input = resolved.req_model_spec || resolved.model_str

    with :ok <- validate_api_key(resolved),
         result <- do_call(method, model_input, messages, final_opts) do
      case result do
        {:ok, _} = success ->
          success

        {:error, reason} ->
          # 尝试 fallback chain
          try_fallback(model_config, messages, opts, method, provider_name, reason)
      end
    end
  end

  defp try_fallback(model_config, messages, opts, method, failed_provider, last_error) do
    case ProviderRegistry.fallback(failed_provider) do
      {:ok, next_provider} ->
        # 用 fallback provider 重新构建配置
        fallback_config = Map.put(model_config, :provider, next_provider)
        resolved = resolve_config(fallback_config, opts)
        final_opts = build_final_opts(resolved, opts)

        model_input = resolved.req_model_spec || resolved.model_str

        case do_call(method, model_input, messages, final_opts) do
          {:ok, _} = success -> success
          {:error, _} -> {:error, :all_providers_exhausted}
        end

      {:error, :no_fallback} ->
        {:error, {:all_providers_exhausted, last_error}}
    end
  end

  defp do_call(:stream_text, model_input, messages, opts) do
    ReqLLM.stream_text(model_input, messages, opts)
  end

  defp do_call(:generate_text, model_input, messages, opts) do
    ReqLLM.generate_text(model_input, messages, opts)
  end

  defp build_final_opts(resolved, runtime_opts) do
    # 从 runtime_opts 中保留非配置项（如 tools）
    base_opts =
      runtime_opts
      |> Keyword.drop([:base_url, :receive_timeout, :headers])

    base_opts
    |> Keyword.put(:receive_timeout, resolved.receive_timeout)
    |> maybe_put_base_url(resolved.base_url)
    |> maybe_put_api_key(resolved.api_key)
    |> maybe_put_req_http_headers(resolved.headers)
  end

  defp maybe_put_base_url(opts, nil), do: opts
  defp maybe_put_base_url(opts, base_url), do: Keyword.put(opts, :base_url, base_url)

  defp maybe_put_api_key(opts, nil), do: opts
  defp maybe_put_api_key(opts, ""), do: opts
  defp maybe_put_api_key(opts, api_key), do: Keyword.put(opts, :api_key, api_key)

  defp maybe_put_req_http_headers(opts, nil), do: opts
  defp maybe_put_req_http_headers(opts, headers) when headers == %{}, do: opts

  defp maybe_put_req_http_headers(opts, headers) do
    req_http_options = Keyword.get(opts, :req_http_options, [])
    existing_headers = req_http_options |> Keyword.get(:headers, []) |> normalize_headers()
    merged_headers = Map.merge(existing_headers, normalize_headers(headers))

    merged_header_list =
      merged_headers
      |> Enum.map(fn {k, v} -> {k, v} end)

    opts
    |> Keyword.put(:req_http_options, Keyword.put(req_http_options, :headers, merged_header_list))
  end

  defp normalize_headers(headers) when is_map(headers) do
    Enum.reduce(headers, %{}, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.reduce(headers, %{}, fn
      {k, v}, acc -> Map.put(acc, to_string(k), v)
      _other, acc -> acc
    end)
  end

  defp normalize_headers(_), do: %{}

  defp resolve_req_provider(provider_name, provider_config) do
    candidate =
      case Map.get(provider_config, :module) do
        Gong.Providers.OpenaiCompatProvider -> "openai_compat"
        # anthropic_compat 厂商实例实际走 ReqLLM 内置 anthropic provider，
        # 以确保使用 /v1/messages 端点与 x-api-key 鉴权。
        Gong.Providers.AnthropicCompatProvider -> "anthropic"
        Gong.Providers.DeepSeek -> "deepseek"
        _ -> provider_name
      end

    candidate_prefix =
      candidate
      |> String.split(":", parts: 2)
      |> hd()

    Enum.find(ReqLLM.Providers.list(), fn provider_id ->
      Atom.to_string(provider_id) == candidate_prefix
    end)
  end

  # 根据 auth_mode 注入鉴权头，仅当 model_config 显式包含 auth_mode 字段时生效
  defp inject_auth_header(headers, %{auth_mode: auth_mode, api_key_env: env_var})
       when is_atom(auth_mode) and is_binary(env_var) do
    case System.get_env(env_var) do
      nil ->
        headers

      api_key ->
        case auth_mode do
          :anthropic_header ->
            # 不覆盖已有的 x-api-key
            Map.put_new(headers, "x-api-key", api_key)

          :bearer ->
            # 不覆盖已有的 authorization
            Map.put_new(headers, "authorization", "Bearer #{api_key}")
        end
    end
  end

  defp inject_auth_header(headers, _model_config), do: headers

  defp validate_api_key(%{api_key_env: env_var, api_key: api_key})
       when is_binary(env_var) and env_var != "" and (is_nil(api_key) or api_key == "") do
    {:error,
     %{
       code: :unauthorized,
       message: "缺少 #{env_var}，请先配置后重试",
       details: %{api_key_env: env_var}
     }}
  end

  defp validate_api_key(_resolved), do: :ok
end
