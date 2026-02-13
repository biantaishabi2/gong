defmodule Gong.Extension.Runner do
  @moduledoc """
  Extension 生命周期管理。

  负责 Extension 的 init → 运行 → cleanup 全流程。
  """

  require Logger

  @type ext_state :: %{module: module(), state: term()}

  @doc "初始化所有 Extension，返回状态列表"
  @spec init_all([module()], keyword()) :: {[ext_state()], [{module(), term()}]}
  def init_all(modules, opts \\ []) do
    Enum.reduce(modules, {[], []}, fn mod, {states, errors} ->
      case mod.init(opts) do
        {:ok, state} ->
          {states ++ [%{module: mod, state: state}], errors}

        {:error, reason} ->
          Logger.warning("Extension #{mod.name()} init 失败: #{inspect(reason)}")
          {states, errors ++ [{mod, reason}]}
      end
    end)
  end

  @doc "获取所有 Extension 提供的工具"
  @spec collect_tools([ext_state()]) :: [module()]
  def collect_tools(ext_states) do
    Enum.flat_map(ext_states, fn %{module: mod} ->
      mod.tools()
    end)
  end

  @doc "获取所有 Extension 提供的命令"
  @spec collect_commands([ext_state()]) :: [map()]
  def collect_commands(ext_states) do
    Enum.flat_map(ext_states, fn %{module: mod} ->
      mod.commands()
    end)
  end

  @doc "获取所有 Extension 提供的 Hook"
  @spec collect_hooks([ext_state()]) :: [module()]
  def collect_hooks(ext_states) do
    Enum.flat_map(ext_states, fn %{module: mod} ->
      mod.hooks()
    end)
  end

  @doc "清理所有 Extension"
  @spec cleanup_all([ext_state()]) :: :ok
  def cleanup_all(ext_states) do
    for %{module: mod, state: state} <- ext_states do
      try do
        mod.cleanup(state)
      rescue
        e ->
          Logger.warning("Extension #{mod.name()} cleanup 异常: #{Exception.message(e)}")
      end
    end

    :ok
  end
end
