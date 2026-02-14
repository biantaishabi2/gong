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
      |> filter_gitignore(base)
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
     Gong.ToolResult.new(
       content <> hint,
       %{files: relative, total: total, truncated: truncated}
     )}
  end

  defp maybe_exclude(files, nil, _base), do: files
  defp maybe_exclude(files, "", _base), do: files

  defp maybe_exclude(files, exclude_pattern, base) do
    excluded = Path.wildcard(Path.join(base, exclude_pattern), match_dot: true) |> MapSet.new()
    Enum.reject(files, &MapSet.member?(excluded, &1))
  end

  # ── .gitignore 过滤 ──

  defp filter_gitignore(files, base) do
    ignored = collect_ignored_files(base)

    if MapSet.size(ignored) == 0 do
      files
    else
      Enum.reject(files, &MapSet.member?(ignored, &1))
    end
  end

  defp collect_ignored_files(base) do
    gitignore_path = Path.join(base, ".gitignore")

    if File.exists?(gitignore_path) do
      patterns = parse_gitignore(gitignore_path)

      patterns
      |> Enum.flat_map(fn pattern ->
        gitignore_to_globs(pattern, base)
        |> Enum.flat_map(&Path.wildcard(&1, match_dot: true))
      end)
      |> MapSet.new()
    else
      MapSet.new()
    end
  end

  defp parse_gitignore(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.reject(&String.starts_with?(&1, "!"))
  end

  defp gitignore_to_globs(pattern, base) do
    # 去掉开头的 /
    pattern =
      if String.starts_with?(pattern, "/") do
        String.slice(pattern, 1..-1//1)
      else
        pattern
      end

    cond do
      # 目录模式：build/ → 匹配目录下所有文件
      String.ends_with?(pattern, "/") ->
        dir = String.trim_trailing(pattern, "/")
        [Path.join(base, "**/" <> dir <> "/**")]

      # 含路径分隔符：相对于 base 的精确路径
      String.contains?(pattern, "/") ->
        [Path.join(base, pattern)]

      # 纯文件名/目录名模式：匹配任意深度
      true ->
        [
          Path.join(base, "**/" <> pattern),
          Path.join(base, "**/" <> pattern <> "/**")
        ]
    end
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
