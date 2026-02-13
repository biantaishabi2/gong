defmodule Gong.Settings do
  @moduledoc """
  设置管理。

  ETS 存储 + JSON 文件持久化。
  支持全局和项目级别配置，项目级覆盖全局。
  """

  @table :gong_settings

  @default_settings %{
    "model" => "deepseek:deepseek-chat",
    "max_tokens" => "8192",
    "temperature" => "0.7"
  }

  @doc "初始化设置管理器"
  @spec init(String.t()) :: :ok
  def init(workspace) do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    # 加载默认值
    for {k, v} <- @default_settings do
      :ets.insert_new(@table, {k, v})
    end

    # 加载全局配置（如有）
    global_file = Path.join([workspace, ".gong", "settings.json"])
    load_file(global_file)

    # 加载项目配置（如有），覆盖全局
    project_file = Path.join([workspace, ".gong", "settings.json"])
    load_file(project_file)

    :ok
  end

  @doc "获取设置值"
  @spec get(String.t()) :: term()
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> Map.get(@default_settings, key)
    end
  end

  @doc "设置值（运行时立即生效）"
  @spec set(String.t(), term()) :: :ok
  def set(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @doc "列出所有设置"
  @spec list() :: map()
  def list do
    @table
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc "清理 ETS 表"
  @spec cleanup() :: :ok
  def cleanup do
    if :ets.info(@table) != :undefined do
      :ets.delete(@table)
    end
    :ok
  end

  # ── 内部 ──

  defp load_file(path) do
    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, map} when is_map(map) ->
              for {k, v} <- map do
                :ets.insert(@table, {k, to_string(v)})
              end
              :ok

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end
  end
end
