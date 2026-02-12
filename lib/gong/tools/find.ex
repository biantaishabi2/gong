defmodule Gong.Tools.Find do
  @moduledoc """
  文件查找 Action。

  通过 glob 模式查找文件，支持排除模式和结果限制。
  截断策略：head（保留开头）。
  """

  use Jido.Action,
    name: "find_files",
    description: "按 glob 模式查找文件",
    schema: [
      pattern: [type: :string, required: true, doc: "glob 模式"],
      path: [type: :string, default: ".", doc: "搜索根路径"],
      exclude: [type: :string, doc: "排除模式（glob）"],
      limit: [type: :non_neg_integer, default: 500, doc: "最大返回数"]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, base} <- resolve_path(params[:path] || "."),
         :ok <- check_exists(base) do
      find_files(base, params.pattern, params[:exclude], params[:limit] || 500)
    end
  end

  defp resolve_path("~/" <> rest) do
    {:ok, Path.join(System.user_home!(), rest) |> Path.expand()}
  end

  defp resolve_path(path), do: {:ok, Path.expand(path)}

  defp check_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "#{path}: No such file or directory (ENOENT)"}
    end
  end

  defp find_files(base, pattern, exclude, limit) do
    glob_pattern = Path.join(base, pattern)

    files =
      Path.wildcard(glob_pattern, match_dot: true)
      |> maybe_exclude(exclude, base)
      |> sort_by_mtime()

    total = length(files)
    truncated = total > limit
    shown = Enum.take(files, limit)

    # 转为相对路径显示
    relative =
      Enum.map(shown, fn f ->
        Path.relative_to(f, base)
      end)

    content = Enum.join(relative, "\n")

    hint =
      if truncated do
        "\n[Showing #{limit} of #{total} files]"
      else
        ""
      end

    {:ok,
     %{
       content: content <> hint,
       files: relative,
       total: total,
       truncated: truncated
     }}
  end

  defp maybe_exclude(files, nil, _base), do: files
  defp maybe_exclude(files, "", _base), do: files

  defp maybe_exclude(files, exclude_pattern, base) do
    excluded = Path.wildcard(Path.join(base, exclude_pattern), match_dot: true) |> MapSet.new()
    Enum.reject(files, &MapSet.member?(excluded, &1))
  end

  defp sort_by_mtime(files) do
    files
    |> Enum.map(fn f ->
      mtime =
        case File.stat(f) do
          {:ok, %{mtime: mtime}} -> mtime
          _ -> {{1970, 1, 1}, {0, 0, 0}}
        end

      {f, mtime}
    end)
    |> Enum.sort_by(fn {_f, mtime} -> mtime end, :desc)
    |> Enum.map(fn {f, _mtime} -> f end)
  end
end
