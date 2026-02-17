defmodule Gong.ExtensionIntegration do
  @moduledoc """
  Extension 集成胶水模块。

  封装 Extension 的 load → init → collect → cleanup 全流程，
  供 AgentLoop 调用以将 Extension 的工具/hooks/命令注入 Agent。
  """

  require Logger

  alias Gong.Extension.{Loader, Runner}

  @type setup_result :: %{
          ext_states: [Runner.ext_state()],
          tools: [module()],
          hooks: [module()]
        }

  @doc """
  加载并初始化 Extension，收集工具/hooks/命令。

  opts:
    - :extension_paths — 扩展目录列表

  返回 `{:ok, setup_result}` 或 `{:error, reason}`。
  """
  @spec setup(keyword()) :: {:ok, setup_result()} | {:error, term()}
  def setup(opts \\ []) do
    paths = Keyword.get(opts, :extension_paths, [])

    if paths == [] do
      {:ok, %{ext_states: [], tools: [], hooks: []}}
    else
      # 验证路径必须是目录
      non_dirs = Enum.reject(paths, &File.dir?/1)

      if non_dirs != [] do
        {:error, "extension_paths 必须是目录路径，以下路径无效: #{inspect(non_dirs)}"}
      else
        with {:ok, modules, _load_errors} <- Loader.load_all(paths),
             {:ok, modules} <- Loader.detect_conflicts(modules) do
          {ext_states, _init_errors} = Runner.init_all(modules, opts)

          tools = Runner.collect_tools(ext_states)
          hooks = Runner.collect_hooks(ext_states)
          commands = Runner.collect_commands(ext_states)

          # 注册命令到 CommandRegistry（容错：跳过格式不正确的命令）
          for cmd <- commands, is_map(cmd), is_map_key(cmd, :name), is_map_key(cmd, :handler) do
            Gong.CommandRegistry.register(
              cmd.name,
              cmd.handler,
              description: Map.get(cmd, :description, ""),
              extension: Map.get(cmd, :extension)
            )
          end

          {:ok, %{ext_states: ext_states, tools: tools, hooks: hooks}}
        end
      end
    end
  rescue
    e ->
      Logger.warning("Extension setup 异常: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  @doc "清理所有 Extension 状态"
  @spec teardown([Runner.ext_state()]) :: :ok
  def teardown(ext_states) do
    Runner.cleanup_all(ext_states)
  end
end
