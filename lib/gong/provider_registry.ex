defmodule Gong.ProviderRegistry do
  @moduledoc """
  Provider 注册表 — ETS 管理多 Provider 实例。

  支持注册、切换、降级链。
  """

  @table :gong_provider_registry
  @current_key :__current_provider__

  @type provider_entry :: %{
          module: module(),
          config: map(),
          priority: integer(),
          timeout: non_neg_integer() | nil
        }

  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :set, :public])
    :ok
  end

  @spec register(String.t(), module(), map(), keyword()) :: :ok | {:error, String.t()}
  def register(name, module, config \\ %{}, opts \\ []) when is_binary(name) do
    ensure_table!()
    priority = Keyword.get(opts, :priority, 0)

    case module.validate_config(config) do
      :ok ->
        timeout = Keyword.get(opts, :timeout)
        entry = %{module: module, config: config, priority: priority, timeout: timeout}
        :ets.insert(@table, {name, entry})

        # 如果是第一个注册的 provider，自动设为当前
        if current() == nil do
          :ets.insert(@table, {@current_key, name})
        end

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec switch(String.t()) :: :ok | {:error, :not_found}
  def switch(name) when is_binary(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, _entry}] ->
        :ets.insert(@table, {@current_key, name})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @spec current() :: {String.t(), provider_entry()} | nil
  def current do
    ensure_table!()

    case :ets.lookup(@table, @current_key) do
      [{@current_key, name}] ->
        case :ets.lookup(@table, name) do
          [{^name, entry}] -> {name, entry}
          [] -> nil
        end

      [] ->
        nil
    end
  end

  @spec list() :: [{String.t(), provider_entry()}]
  def list do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.reject(fn {key, _} -> key == @current_key end)
    |> Enum.sort_by(fn {_name, entry} -> entry.priority end, :desc)
  end

  @doc "降级：按优先级尝试下一个 provider"
  @spec fallback(String.t()) :: {:ok, String.t()} | {:error, :no_fallback}
  def fallback(failed_name) do
    ensure_table!()

    candidates =
      list()
      |> Enum.reject(fn {name, _} -> name == failed_name end)

    case candidates do
      [{next_name, _} | _] ->
        switch(next_name)
        {:ok, next_name}

      [] ->
        {:error, :no_fallback}
    end
  end

  @doc "查询指定 provider 的超时配置"
  @spec get_timeout(String.t()) :: non_neg_integer() | nil
  def get_timeout(name) when is_binary(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, entry}] -> Map.get(entry, :timeout)
      [] -> nil
    end
  end

  @doc "获取 provider 的重试配置"
  @spec get_retry_config(String.t()) :: map()
  def get_retry_config(provider) when is_binary(provider) do
    ensure_table!()

    # 从注册的 provider 配置中获取重试设置，默认 max_retries=2
    case :ets.lookup(@table, provider) do
      [{^provider, entry}] ->
        Map.get(entry, :retry_config, %{max_retries: 2})

      [] ->
        # 未注册的 provider 返回默认配置（不禁用重试）
        %{max_retries: 2}
    end
  end

  @doc "根据 provider name 返回完整配置（base_url/api_key_env/headers/timeout）"
  @spec resolve_provider_config(String.t()) :: {:ok, map()} | {:error, :not_found}
  def resolve_provider_config(name) when is_binary(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, entry}] ->
        provider_config =
          entry.config
          |> Map.put(:timeout, entry.timeout)
          |> Map.put(:module, entry.module)
          |> Map.put(:priority, entry.priority)

        {:ok, provider_config}

      [] ->
        {:error, :not_found}
    end
  end

  @doc "返回按优先级排列的所有可用 provider 列表，供 Router 依次尝试"
  @spec fallback_chain() :: [String.t()]
  def fallback_chain do
    list()
    |> Enum.map(fn {name, _entry} -> name end)
  end

  @doc "根据 model_config 中的 :provider 字段查找对应 ProviderRegistry entry"
  @spec get_provider_for_model(map()) :: {:ok, {String.t(), provider_entry()}} | {:error, :not_found}
  def get_provider_for_model(%{provider: provider_name}) when is_binary(provider_name) do
    ensure_table!()

    case :ets.lookup(@table, provider_name) do
      [{^provider_name, entry}] -> {:ok, {provider_name, entry}}
      [] -> {:error, :not_found}
    end
  end

  def get_provider_for_model(_), do: {:error, :not_found}

  @spec cleanup() :: :ok
  def cleanup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  end

  defp ensure_table! do
    if :ets.whereis(@table) == :undefined do
      init()
    end
  end
end
