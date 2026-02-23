defmodule Gong.LLMRouter do
  @moduledoc """
  LLM 统一路由入口。

  收敛 AgentLoop 和 Compaction.Summarizer 两条独立的 ReqLLM 直连分支，
  按 runtime > model > provider > default 优先级合并配置，
  通过 ProviderRegistry 获取运行时策略后委托 ReqLLM 执行。
  """

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

    final_headers =
      (provider_headers || %{})
      |> Map.merge(model_headers || %{})
      |> Map.merge(runtime_headers || %{})

    model_str = "#{provider_name}:#{Map.get(model_config, :model_id, "deepseek-chat")}"

    %{
      model_str: model_str,
      base_url: final_base_url,
      headers: final_headers,
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

    case do_call(method, resolved.model_str, messages, final_opts) do
      {:ok, _} = success ->
        success

      {:error, reason} = _error ->
        # 尝试 fallback chain
        try_fallback(model_config, messages, opts, method, provider_name, reason)
    end
  end

  defp try_fallback(model_config, messages, opts, method, failed_provider, last_error) do
    case ProviderRegistry.fallback(failed_provider) do
      {:ok, next_provider} ->
        # 用 fallback provider 重新构建配置
        fallback_config = Map.put(model_config, :provider, next_provider)
        resolved = resolve_config(fallback_config, opts)
        final_opts = build_final_opts(resolved, opts)

        case do_call(method, resolved.model_str, messages, final_opts) do
          {:ok, _} = success -> success
          {:error, _} -> {:error, :all_providers_exhausted}
        end

      {:error, :no_fallback} ->
        {:error, {:all_providers_exhausted, last_error}}
    end
  end

  defp do_call(:stream_text, model_str, messages, opts) do
    ReqLLM.stream_text(model_str, messages, opts)
  end

  defp do_call(:generate_text, model_str, messages, opts) do
    ReqLLM.generate_text(model_str, messages, opts)
  end

  defp build_final_opts(resolved, runtime_opts) do
    # 从 runtime_opts 中保留非配置项（如 tools）
    base_opts =
      runtime_opts
      |> Keyword.drop([:base_url, :receive_timeout, :headers])

    base_opts
    |> Keyword.put(:receive_timeout, resolved.receive_timeout)
    |> maybe_put_base_url(resolved.base_url)
    |> maybe_put_headers(resolved.headers)
  end

  defp maybe_put_base_url(opts, nil), do: opts
  defp maybe_put_base_url(opts, base_url), do: Keyword.put(opts, :base_url, base_url)

  defp maybe_put_headers(opts, nil), do: opts
  defp maybe_put_headers(opts, headers) when headers == %{}, do: opts
  defp maybe_put_headers(opts, headers), do: Keyword.put(opts, :headers, headers)
end
