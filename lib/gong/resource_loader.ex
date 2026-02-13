defmodule Gong.ResourceLoader do
  @moduledoc """
  资源发现和加载。

  扫描 .gong/context/ 目录下的 .md 文件，返回资源列表。
  """

  @doc "加载指定目录列表下的资源文件"
  @spec load([Path.t()]) :: {:ok, [map()]} | {:error, term()}
  def load(paths) do
    resources =
      paths
      |> Enum.flat_map(fn base_dir ->
        context_dir = Path.join(base_dir, "context")

        if File.dir?(context_dir) do
          context_dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.sort()
          |> Enum.map(fn filename ->
            full_path = Path.join(context_dir, filename)
            content = File.read!(full_path)
            %{name: filename, content: content, path: full_path}
          end)
        else
          []
        end
      end)

    {:ok, resources}
  end
end
