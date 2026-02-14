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
