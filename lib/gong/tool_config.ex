defmodule Gong.ToolConfig do
  @moduledoc """
  工具配置系统 — 管理 Agent 激活的工具集。

  支持预设组合（default/full/readonly）和运行时动态切换。
  默认激活 4 个核心工具（read/write/edit/bash），其余按需开启。
  """

  @all_tools [:read, :write, :edit, :bash, :grep, :find, :ls]

  @presets %{
    default: [:read, :write, :edit, :bash],
    full: @all_tools,
    readonly: [:read, :grep, :find, :ls]
  }

  @table :gong_tool_config

  @doc "初始化工具配置，默认激活 4 个核心工具"
  def init(opts \\ []) do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:named_table, :set, :public])
    end

    preset_name = Keyword.get(opts, :preset, :default)
    tools = Map.get(@presets, preset_name, @all_tools)
    :ets.insert(@table, {:active_tools, tools})
    :ok
  end

  @doc "获取预设的工具列表"
  def preset(name) when is_atom(name) do
    case Map.fetch(@presets, name) do
      {:ok, tools} -> {:ok, tools}
      :error -> {:error, "unknown preset: #{name}"}
    end
  end

  @doc "获取当前激活的工具列表"
  def active_tools do
    case :ets.lookup(@table, :active_tools) do
      [{:active_tools, tools}] -> tools
      [] -> @all_tools
    end
  end

  @doc "设置激活工具列表（运行时切换）"
  def set_active_tools(tool_names) when is_list(tool_names) do
    case validate(tool_names) do
      :ok ->
        :ets.insert(@table, {:active_tools, tool_names})
        :ok

      {:error, _} = err ->
        err
    end
  end

  @doc "校验工具名列表是否合法"
  def validate(tool_names) when is_list(tool_names) do
    if tool_names == [] do
      {:error, "tool list cannot be empty"}
    else
      invalid = Enum.reject(tool_names, &(&1 in @all_tools))

      if invalid == [] do
        :ok
      else
        {:error, "unknown tools: #{Enum.join(Enum.map(invalid, &to_string/1), ", ")}"}
      end
    end
  end

  @doc "清理 ETS 表"
  def cleanup do
    if :ets.info(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  end

  @doc "返回所有可用工具名"
  def all_tools, do: @all_tools

  @doc "返回所有预设名"
  def presets, do: Map.keys(@presets)
end
