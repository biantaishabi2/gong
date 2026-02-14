defmodule Gong.CommandRegistry do
  @moduledoc """
  Command 注册表 — 管理 Extension 注册的自定义命令。

  命令格式：/command_name [args]
  """

  @table :gong_command_registry

  @type command :: %{
          name: String.t(),
          description: String.t(),
          handler: (map() -> {:ok, String.t()} | {:error, String.t()}),
          extension: String.t() | nil
        }

  @doc "初始化命令注册表"
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :set, :public])
    :ok
  end

  @doc "注册命令"
  @spec register(String.t(), function(), keyword()) :: :ok
  def register(name, handler, opts \\ []) when is_binary(name) and is_function(handler, 1) do
    ensure_table!()

    command = %{
      name: name,
      description: Keyword.get(opts, :description, ""),
      handler: handler,
      extension: Keyword.get(opts, :extension)
    }

    :ets.insert(@table, {name, command})
    :ok
  end

  @doc "执行命令"
  @spec execute(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute(name, args \\ %{}) when is_binary(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, command}] ->
        try do
          command.handler.(args)
        rescue
          e -> {:error, Exception.message(e)}
        end

      [] ->
        {:error, "命令不存在: /#{name}"}
    end
  end

  @doc "列出所有已注册命令"
  @spec list() :: [command()]
  def list do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.map(fn {_name, command} -> command end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "检查命令是否存在"
  @spec exists?(String.t()) :: boolean()
  def exists?(name) when is_binary(name) do
    ensure_table!()
    :ets.lookup(@table, name) != []
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
