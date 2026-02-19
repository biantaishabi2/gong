defmodule Gong.Retry do
  @moduledoc """
  LLM 请求自动重试（指数退避）。

  核心判定优先级：
  1. 错误类型（type/error_type/code）
  2. HTTP 状态码（429/5xx）
  3. 标签（tags/metadata tags）
  """

  @max_retries 3
  @base_delay_ms 1000

  @type error_class :: :transient | :context_overflow | :permanent
  @type retry_source :: :error_type | :http_status | :tag | :pattern | :none
  @type retry_reason ::
          :retryable_error_type
          | :non_retryable_error_type
          | :retryable_http_status
          | :non_retryable_http_status
          | :retryable_tag
          | :non_retryable_tag
          | :retryable_pattern
          | :context_overflow_pattern
          | :unknown

  @type retry_decision :: %{
          retryable: boolean(),
          error_class: error_class(),
          source: retry_source(),
          reason: retry_reason(),
          matched: term() | nil
        }

  @retryable_error_types MapSet.new([
                           "timeout",
                           "request_timeout",
                           "connection_error",
                           "connection_reset",
                           "connection_refused",
                           "connection_terminated",
                           "transport_reset",
                           "network_error",
                           "econnreset",
                           "econnrefused",
                           "etimedout",
                           "fetch_failed"
                         ])
  @context_overflow_error_types MapSet.new([
                                  "context_overflow",
                                  "context_length_exceeded",
                                  "token_limit_exceeded",
                                  "max_tokens_exceeded"
                                ])
  @non_retryable_error_types MapSet.new([
                               "invalid_request",
                               "invalid_argument",
                               "authentication_error",
                               "unauthorized",
                               "forbidden",
                               "bad_request",
                               "content_policy"
                             ])
  @retryable_status_codes MapSet.new([429])
  @non_retryable_status_codes MapSet.new([400, 401, 403, 404, 422])
  @retryable_tags MapSet.new([
                    "retryable",
                    "transient",
                    "network",
                    "timeout",
                    "connection_reset",
                    "rate_limit"
                  ])
  @non_retryable_tags MapSet.new(["non_retryable", "invalid_request", "context_overflow"])

  @doc "将错误分类为 transient / context_overflow / permanent"
  @spec classify_error(term()) :: error_class()
  def classify_error(error) do
    error
    |> is_retryable_error()
    |> Map.fetch!(:error_class)
  end

  @doc """
  按“错误类型 > HTTP 状态码 > 标签”输出统一判定结果。
  """
  @spec is_retryable_error(term()) :: retry_decision()
  def is_retryable_error(error) do
    with {:error, :no_match} <- match_error_type(error),
         {:error, :no_match} <- match_http_status(error),
         {:error, :no_match} <- match_tags(error),
         {:error, :no_match} <- match_fallback_pattern(error) do
      decision(false, :permanent, :none, :unknown, nil)
    else
      {:ok, decision} -> decision
    end
  end

  @doc "JS 风格兼容入口（与 is_retryable_error/1 等价）"
  @spec isRetryableError(term()) :: retry_decision()
  def isRetryableError(error), do: is_retryable_error(error)

  @doc "是否应该重试"
  @spec should_retry?(error_class() | retry_decision(), non_neg_integer()) :: boolean()
  def should_retry?(%{error_class: :transient}, attempt) when attempt < @max_retries, do: true
  def should_retry?(%{retryable: true}, attempt) when attempt < @max_retries, do: true
  def should_retry?(:transient, attempt) when attempt < @max_retries, do: true
  def should_retry?(_, _), do: false

  @doc "计算第 N 次重试的延迟毫秒数（指数退避）"
  @spec delay_ms(non_neg_integer()) :: non_neg_integer()
  def delay_ms(attempt) do
    trunc(@base_delay_ms * :math.pow(2, attempt))
  end

  @doc "返回最大重试次数"
  @spec max_retries() :: non_neg_integer()
  def max_retries, do: @max_retries

  # ── 错误模式匹配 ──

  defp match_error_type(error) do
    case extract_error_type(error) do
      nil ->
        {:error, :no_match}

      type ->
        cond do
          MapSet.member?(@retryable_error_types, type) ->
            {:ok, decision(true, :transient, :error_type, :retryable_error_type, type)}

          MapSet.member?(@context_overflow_error_types, type) ->
            {:ok,
             decision(false, :context_overflow, :error_type, :non_retryable_error_type, type)}

          MapSet.member?(@non_retryable_error_types, type) ->
            {:ok, decision(false, :permanent, :error_type, :non_retryable_error_type, type)}

          true ->
            {:error, :no_match}
        end
    end
  end

  defp match_http_status(error) do
    case extract_http_status(error) do
      nil ->
        {:error, :no_match}

      status when status in 500..599 ->
        {:ok, decision(true, :transient, :http_status, :retryable_http_status, status)}

      status ->
        cond do
          MapSet.member?(@retryable_status_codes, status) ->
            {:ok, decision(true, :transient, :http_status, :retryable_http_status, status)}

          MapSet.member?(@non_retryable_status_codes, status) ->
            {:ok, decision(false, :permanent, :http_status, :non_retryable_http_status, status)}

          true ->
            {:error, :no_match}
        end
    end
  end

  defp match_tags(error) do
    tags = extract_tags(error)

    cond do
      tags == [] ->
        {:error, :no_match}

      retry_tag = Enum.find(tags, &MapSet.member?(@retryable_tags, &1)) ->
        {:ok, decision(true, :transient, :tag, :retryable_tag, retry_tag)}

      non_retry_tag = Enum.find(tags, &MapSet.member?(@non_retryable_tags, &1)) ->
        {:ok, decision(false, :permanent, :tag, :non_retryable_tag, non_retry_tag)}

      true ->
        {:error, :no_match}
    end
  end

  defp match_fallback_pattern(error) do
    error_str = error_to_pattern_string(error)

    cond do
      context_overflow?(error_str) ->
        {:ok,
         decision(
           false,
           :context_overflow,
           :pattern,
           :context_overflow_pattern,
           "context_overflow"
         )}

      rate_limit?(error_str) or connection_error?(error_str) ->
        {:ok, decision(true, :transient, :pattern, :retryable_pattern, "network_or_ratelimit")}

      true ->
        {:error, :no_match}
    end
  end

  defp error_to_pattern_string(error) when is_binary(error), do: error

  defp error_to_pattern_string(error) when is_atom(error) or is_number(error),
    do: to_string(error)

  defp error_to_pattern_string(error) do
    try do
      to_string(error)
    rescue
      Protocol.UndefinedError -> inspect(error)
    end
  end

  defp decision(retryable, error_class, source, reason, matched) do
    %{
      retryable: retryable,
      error_class: error_class,
      source: source,
      reason: reason,
      matched: matched
    }
  end

  defp extract_error_type(error) when is_map(error) do
    error
    |> first_present([
      :type,
      :error_type,
      :errorType,
      :code,
      "type",
      "error_type",
      "errorType",
      "code"
    ])
    |> normalize_token()
  end

  defp extract_error_type(_), do: nil

  defp extract_http_status(error) when is_map(error) do
    value =
      first_present(error, [
        :status,
        :status_code,
        :statusCode,
        :http_status,
        "status",
        "status_code",
        "statusCode",
        "http_status"
      ]) ||
        error
        |> first_present([:details, "details", :response, "response"])
        |> first_present([
          :status,
          :status_code,
          :statusCode,
          :http_status,
          "status",
          "status_code",
          "statusCode",
          "http_status"
        ])

    normalize_status(value)
  end

  defp extract_http_status(_), do: nil

  defp extract_tags(error) when is_map(error) do
    direct_tags = first_present(error, [:tags, "tags"])
    metadata = first_present(error, [:metadata, "metadata", :details, "details"])
    metadata_tags = first_present(metadata, [:tags, "tags"])

    (normalize_tags(direct_tags) ++ normalize_tags(metadata_tags))
    |> Enum.uniq()
  end

  defp extract_tags(_), do: []

  defp first_present(nil, _keys), do: nil

  defp first_present(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key ->
      if Map.has_key?(map, key), do: Map.get(map, key), else: nil
    end)
  end

  defp first_present(_, _keys), do: nil

  defp normalize_status(value) when is_integer(value), do: value

  defp normalize_status(value) when is_binary(value) do
    case Integer.parse(value) do
      {status, ""} -> status
      _ -> nil
    end
  end

  defp normalize_status(_), do: nil

  defp normalize_tags(tags) when is_list(tags) do
    Enum.map(tags, &normalize_token/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(tags) when is_map(tags) do
    tags
    |> Enum.filter(fn {_k, v} -> v in [true, "true", 1] end)
    |> Enum.map(fn {k, _v} -> normalize_token(k) end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",", trim: true)
    |> normalize_tags()
  end

  defp normalize_tags(_), do: []

  defp normalize_token(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> normalize_token()
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace("-", "_")
    |> case do
      "" -> nil
      token -> token
    end
  end

  defp normalize_token(_), do: nil

  defp rate_limit?(str), do: str =~ ~r/429|rate.?limit/i
  defp connection_error?(str), do: str =~ ~r/connect|timeout|ECONNREFUSED|ETIMEDOUT|fetch failed/i

  defp context_overflow?(str) do
    str =~ ~r/too long|exceeds.*context|token.*exceed|maximum prompt|reduce.*length/i
  end
end
