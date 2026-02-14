defmodule Gong.Tools.Write do
  @moduledoc """
  文件写入 Action。

  覆盖写入指定文件，自动创建父目录。
  """

  use Jido.Action,
    name: "write_file",
    description: "写入文件内容（覆盖）",
    schema: [
      file_path: [type: :string, required: true, doc: "文件绝对路径"],
      content: [type: :string, required: true, doc: "写入内容"]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, path} <- resolve_path(params.file_path),
         :ok <- check_not_directory(path),
         :ok <- ensure_parent_dir(path),
         :ok <- write_file(path, params.content) do
      {:ok,
       Gong.ToolResult.new(
         "File written: #{path} (#{byte_size(params.content)} bytes)",
         %{file_path: path, bytes_written: byte_size(params.content)}
       )}
    end
  end

  defp resolve_path(path) when not is_binary(path) do
    {:error, "参数错误：file_path 必须是字符串"}
  end

  defp resolve_path("~/" <> rest) do
    {:ok, Path.join(System.user_home!(), rest) |> Path.expand()}
  end

  defp resolve_path(path), do: {:ok, Path.expand(path)}

  defp check_not_directory(path) do
    if File.dir?(path) do
      {:error, "#{path}: Is a directory, cannot write"}
    else
      :ok
    end
  end

  defp ensure_parent_dir(path) do
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, "#{dir}: Cannot create directory (#{reason})"}
    end
  end

  defp write_file(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, :eacces} -> {:error, "#{path}: Permission denied (EACCES)"}
      {:error, reason} -> {:error, "#{path}: Write failed (#{reason})"}
    end
  end
end
