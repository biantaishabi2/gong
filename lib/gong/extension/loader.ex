defmodule Gong.Extension.Loader do
  @moduledoc """
  Extension 发现和加载。

  扫描目录中的 .ex 文件，动态编译并验证 behaviour 实现。
  """

  require Logger

  @doc "扫描目录列表，返回 .ex 文件列表。支持 no_extensions 选项。"
  @spec discover([Path.t()], keyword()) :: {:ok, [Path.t()]} | {:error, term()}
  def discover(paths, opts \\ []) do
    if Keyword.get(opts, :no_extensions, false) do
      {:ok, []}
    else
      files =
        paths
        |> Enum.filter(&File.dir?/1)
        |> Enum.flat_map(fn dir ->
          dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".ex"))
          |> Enum.map(&Path.join(dir, &1))
        end)
        |> Enum.sort()

      {:ok, files}
    end
  end

  @doc "加载单个 Extension 文件"
  @spec load(Path.t()) :: {:ok, module()} | {:error, term()}
  def load(path) do
    try do
      modules = Code.compile_file(path)
      # 查找实现了 Gong.Extension behaviour 的模块
      ext_module =
        Enum.find_value(modules, fn {mod, _bytecode} ->
          if implements_extension?(mod), do: mod
        end)

      if ext_module do
        {:ok, ext_module}
      else
        {:error, "no Gong.Extension behaviour found in #{path}"}
      end
    rescue
      e ->
        {:error, "compile error in #{Path.basename(path)}: #{Exception.message(e)}"}
    end
  end

  @doc "发现并加载全部 Extension，失败隔离"
  @spec load_all([Path.t()]) :: {:ok, [module()], [{Path.t(), term()}]}
  def load_all(paths) do
    {:ok, files} = discover(paths)

    {modules, errors} =
      Enum.reduce(files, {[], []}, fn file, {mods, errs} ->
        case load(file) do
          {:ok, mod} ->
            {mods ++ [mod], errs}

          {:error, reason} ->
            Logger.warning("Extension 加载失败: #{file} - #{inspect(reason)}")
            {mods, errs ++ [{file, reason}]}
        end
      end)

    {:ok, modules, errors}
  end

  @doc "检测跨扩展重名工具/命令冲突"
  @spec detect_conflicts([module()]) :: {:ok, [module()]} | {:error, String.t()}
  def detect_conflicts(modules) when is_list(modules) do
    # 收集所有工具/命令名
    names =
      Enum.flat_map(modules, fn mod ->
        if function_exported?(mod, :name, 0) do
          [mod.name()]
        else
          []
        end
      end)

    duplicates = names -- Enum.uniq(names)

    if duplicates == [] do
      {:ok, modules}
    else
      {:error, "extension conflict: duplicate names #{inspect(Enum.uniq(duplicates))}"}
    end
  end

  @doc "解析子路径 import 到绝对路径"
  @spec resolve_imports(Path.t(), [String.t()]) :: {:ok, [Path.t()]} | {:error, term()}
  def resolve_imports(base_dir, import_paths) when is_list(import_paths) do
    resolved =
      Enum.map(import_paths, fn path ->
        if String.starts_with?(path, "./") do
          Path.join(base_dir, String.trim_leading(path, "./"))
        else
          path
        end
      end)

    missing = Enum.reject(resolved, &File.exists?/1)

    if missing == [] do
      {:ok, resolved}
    else
      {:error, "import not found: #{inspect(missing)}"}
    end
  end

  defp implements_extension?(module) do
    behaviours = module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()

    Gong.Extension in behaviours
  rescue
    _ -> false
  end
end
