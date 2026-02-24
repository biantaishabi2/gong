defmodule Gong.Settings do
  @moduledoc """
  设置管理。

  ETS 存储 + JSON 文件持久化。
  默认使用全局配置文件 `~/.gong/settings.json`。
  测试可通过 `GONG_SETTINGS_FILE` 覆盖路径。
  """

  @table :gong_settings

  @default_settings %{
    "model" => "minimax",
    "max_tokens" => "8192",
    "temperature" => "0.7",
    "max_iterations" => "infinity"
  }

  @doc "初始化设置管理器"
  @spec init(String.t()) :: :ok
  def init(_workspace) do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    # 加载默认值
    for {k, v} <- @default_settings do
      :ets.insert_new(@table, {k, v})
    end

    load_file(settings_file())

    :ok
  end

  @doc "获取设置值"
  @spec get(String.t()) :: term()
  def get(key) do
    if :ets.info(@table) == :undefined do
      Map.get(@default_settings, key)
    else
      case :ets.lookup(@table, key) do
        [{^key, value}] -> value
        [] -> Map.get(@default_settings, key)
      end
    end
  end

  @doc "获取整数值设置，支持 :infinity 特殊值"
  @spec get_integer(String.t(), integer() | :infinity) :: integer() | :infinity
  def get_integer(key, default) do
    case get(key) do
      "infinity" ->
        :infinity

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> default
        end

      value when is_integer(value) ->
        value

      _ ->
        default
    end
  end

  @doc "设置值（运行时立即生效）"
  @spec set(String.t(), term()) :: :ok
  def set(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  end

  @doc "获取当前模型设置"
  @spec get_model() :: String.t()
  def get_model do
    get("model")
  end

  @doc """
  持久化设置模型（原子写）。

  返回归一化后的模型信息（短名 + 完整名）。
  """
  @spec set_model(String.t(), String.t()) ::
          {:ok, %{short: String.t(), model: String.t()}}
          | {:error, :unknown_provider | :persist_failed}
  def set_model(workspace, model_name) when is_binary(workspace) and is_binary(model_name) do
    if :ets.info(@table) == :undefined do
      init(workspace)
    end

    case Gong.ModelRegistry.resolve_registered_model(model_name) do
      {:ok, resolved} ->
        :ets.insert(@table, {"model", resolved.short})

        case persist() do
          :ok ->
            {:ok, %{short: resolved.short, model: resolved.model}}

          {:error, _reason} ->
            {:error, :persist_failed}
        end

      {:error, :unknown_provider} ->
        {:error, :unknown_provider}
    end
  end

  @doc "列出所有设置"
  @spec list() :: map()
  def list do
    @table
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc "重新读取配置文件刷新 ETS"
  @spec reload(String.t()) :: :ok
  def reload(_workspace) do
    # 清空当前值并重新加载
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    # 重新加载默认值 + 文件
    for {k, v} <- @default_settings do
      :ets.insert(@table, {k, v})
    end

    load_file(settings_file())
    :ok
  end

  @doc """
  语义化类型获取：区分 [] 和 nil/缺失。

  - `[]`（空数组）= 阻止全部（explicit empty）
  - `nil` / 缺失 = 不过滤（no filter）
  """
  @spec get_typed(String.t(), atom()) :: term()
  def get_typed(key, type \\ :string) do
    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        case type do
          :list ->
            cond do
              is_list(value) -> value
              value == "[]" -> []
              is_binary(value) -> Jason.decode!(value)
              true -> value
            end

          _ ->
            value
        end

      [] ->
        nil
    end
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

  defp persist do
    file = settings_file()
    dir = Path.dirname(file)
    tmp = file <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         content <- list() |> Jason.encode!(pretty: true),
         :ok <- File.write(tmp, content),
         {:ok, fd} <- :file.open(String.to_charlist(tmp), [:read, :raw]),
         :ok <- :file.sync(fd),
         :ok <- :file.close(fd),
         :ok <- File.rename(tmp, file) do
      :ok
    else
      {:error, reason} ->
        _ = File.rm(tmp)
        {:error, reason}

      reason ->
        _ = File.rm(tmp)
        {:error, reason}
    end
  end

  defp settings_file do
    case System.get_env("GONG_SETTINGS_FILE") do
      path when is_binary(path) and path != "" -> path
      _ -> Path.join([System.user_home!(), ".gong", "settings.json"])
    end
  end
end
