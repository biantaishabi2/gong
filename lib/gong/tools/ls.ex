defmodule Gong.Tools.Ls do
  @moduledoc """
  目录列表 Action。

  列出指定目录的内容，包括文件类型、大小、修改时间。
  截断策略：head（保留开头）。
  """

  use Jido.Action,
    name: "list_directory",
    description: "列出目录内容",
    schema: [
      path: [type: :string, required: true, doc: "目录路径"]
    ]

  @max_entries 1000

  @impl true
  def run(params, _context) do
    with {:ok, path} <- resolve_path(params.path),
         :ok <- check_directory(path) do
      list_entries(path)
    end
  end

  defp resolve_path(path) when not is_binary(path) do
    {:error, "参数错误：path 必须是字符串"}
  end

  defp resolve_path("~/" <> rest) do
    {:ok, Path.join(System.user_home!(), rest) |> Path.expand()}
  end

  defp resolve_path(path), do: {:ok, Path.expand(path)}

  defp check_directory(path) do
    cond do
      not File.exists?(path) ->
        {:error, "#{path}: No such file or directory (ENOENT)"}

      not File.dir?(path) ->
        {:error, "#{path}: Not a directory"}

      true ->
        case File.stat(path) do
          {:ok, %{access: access}} when access in [:read, :read_write] -> :ok
          {:ok, _} -> {:error, "#{path}: Permission denied (EACCES)"}
          {:error, reason} -> {:error, "#{path}: #{inspect(reason)}"}
        end
    end
  end

  defp list_entries(path) do
    case File.ls(path) do
      {:ok, names} ->
        entries =
          names
          |> Enum.sort()
          |> Enum.map(fn name -> build_entry(path, name) end)

        total = length(entries)
        truncated = total > @max_entries
        shown = Enum.take(entries, @max_entries)

        content = format_entries(shown)

        hint =
          if truncated do
            "\n[Showing #{@max_entries} of #{total} entries]"
          else
            ""
          end

        {:ok,
         Gong.ToolResult.new(
           content <> hint,
           %{entries: shown, total: total, truncated: truncated}
         )}

      {:error, reason} ->
        {:error, "#{path}: #{inspect(reason)}"}
    end
  end

  defp build_entry(parent, name) do
    full = Path.join(parent, name)

    case File.lstat(full) do
      {:ok, stat} ->
        %{
          name: name,
          type: to_string(stat.type),
          size: stat.size,
          mtime: format_mtime(stat.mtime)
        }

      {:error, _} ->
        %{name: name, type: "unknown", size: 0, mtime: nil}
    end
  end

  defp format_mtime({{y, m, d}, {h, mi, s}}) do
    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B", [y, m, d, h, mi, s])
    |> IO.iodata_to_binary()
  end

  defp format_mtime(_), do: nil

  defp format_entries(entries) do
    entries
    |> Enum.map(fn e ->
      type_indicator = type_suffix(e.type)
      size_str = format_size(e.size)
      "#{String.pad_trailing(size_str, 10)} #{e.name}#{type_indicator}"
    end)
    |> Enum.join("\n")
  end

  defp type_suffix("directory"), do: "/"
  defp type_suffix("symlink"), do: "@"
  defp type_suffix(_), do: ""

  defp format_size(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)}K"
  defp format_size(bytes), do: "#{div(bytes, 1024 * 1024)}M"
end
