defmodule Gong.Extension.Loader do
  @moduledoc """
  Extension 发现和加载。

  扫描目录中的 .ex 文件，动态编译并验证 behaviour 实现。
  """

  require Logger

  @doc "扫描目录列表，返回 .ex 文件列表"
  @spec discover([Path.t()]) :: {:ok, [Path.t()]} | {:error, term()}
  def discover(paths) do
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

  defp implements_extension?(module) do
    behaviours = module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()

    Gong.Extension in behaviours
  rescue
    _ -> false
  end
end
