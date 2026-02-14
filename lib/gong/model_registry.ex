defmodule Gong.ModelRegistry do
  @moduledoc """
  模型注册表 — ETS 存储模型配置，支持运行时切换。

  注册多个 LLM provider/model 组合，运行时动态切换当前活跃模型。
  """

  @table :gong_model_registry
  @current_key :__current_model__
  @default_model_name :default

  @type model_config :: %{
          provider: String.t(),
          model_id: String.t(),
          api_key_env: String.t(),
          context_window: non_neg_integer() | nil
        }

  # ── 初始化 ──

  @doc "初始化 ETS 表，设默认模型"
  @spec init(model_config() | nil) :: :ok
  def init(default_config \\ nil) do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :set, :public])

    config = default_config || %{
      provider: "deepseek",
      model_id: "deepseek-chat",
      api_key_env: "DEEPSEEK_API_KEY"
    }

    :ets.insert(@table, {@default_model_name, config})
    :ets.insert(@table, {@current_key, @default_model_name})
    :ok
  end

  # ── 注册 ──

  @doc "注册模型配置"
  @spec register(atom(), model_config()) :: :ok
  def register(name, config) when is_atom(name) and is_map(config) do
    ensure_table!()
    :ets.insert(@table, {name, config})
    :ok
  end

  # ── 切换 ──

  @doc "切换当前模型，不存在则保持当前"
  @spec switch(atom()) :: :ok | {:error, :not_found}
  def switch(name) when is_atom(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, _config}] ->
        :ets.insert(@table, {@current_key, name})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  # ── 查询 ──

  @doc "返回当前模型配置"
  @spec current_model() :: {atom(), model_config()} | nil
  def current_model do
    ensure_table!()

    case :ets.lookup(@table, @current_key) do
      [{@current_key, name}] ->
        case :ets.lookup(@table, name) do
          [{^name, config}] -> {name, config}
          [] -> nil
        end

      [] ->
        nil
    end
  end

  @doc "返回当前模型的 ReqLLM 格式字符串（provider:model_id）"
  @spec current_model_string() :: String.t()
  def current_model_string do
    case current_model() do
      {_name, %{provider: provider, model_id: model_id}} ->
        "#{provider}:#{model_id}"

      nil ->
        "deepseek:deepseek-chat"
    end
  end

  @doc "列出所有已注册模型"
  @spec list() :: [{atom(), model_config()}]
  def list do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.reject(fn {key, _} -> key == @current_key end)
    |> Enum.sort_by(fn {name, _} -> name end)
  end

  @doc "校验模型是否可用（API key 环境变量存在）"
  @spec validate(atom()) :: :ok | {:error, String.t()}
  def validate(name) when is_atom(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, %{api_key_env: env_var}}] ->
        if System.get_env(env_var) do
          :ok
        else
          {:error, "API key 环境变量 #{env_var} 未设置"}
        end

      [] ->
        {:error, "模型 #{name} 未注册"}
    end
  end

  # ── 上下文窗口 ──

  @default_context_window 128_000

  @doc "返回模型的上下文窗口大小（默认 128000）"
  @spec get_context_window(atom()) :: non_neg_integer()
  def get_context_window(name) when is_atom(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, config}] ->
        Map.get(config, :context_window) || @default_context_window

      [] ->
        @default_context_window
    end
  end

  @doc "补充缺失的可选字段为默认值"
  @spec apply_defaults(model_config()) :: model_config()
  def apply_defaults(config) when is_map(config) do
    Map.merge(
      %{api_key_env: "", context_window: @default_context_window},
      config
    )
  end

  @doc "清除带 auth 引用的模型条目"
  @spec clear_auth_references() :: :ok
  def clear_auth_references do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.each(fn
      {@current_key, _} -> :ok
      {name, config} when is_map(config) ->
        if Map.has_key?(config, :auth_ref) do
          :ets.delete(@table, name)
        end
      _ -> :ok
    end)

    :ok
  end

  # ── 清理 ──

  @doc "清理 ETS 表"
  @spec cleanup() :: :ok
  def cleanup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  end

  # ── 私有 ──

  defp ensure_table! do
    if :ets.whereis(@table) == :undefined do
      init()
    end
  end
end
