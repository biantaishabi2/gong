defmodule Gong.Tools.Truncate do
  @moduledoc """
  文件截断工具 Action。

  包装 Gong.Truncate 为工具，支持 max_lines 参数。
  """

  use Jido.Action,
    name: "truncate_file",
    description: "读取并截断文件内容",
    schema: [
      file_path: [type: :string, required: true, doc: "文件路径"],
      max_lines: [type: :integer, default: 100, doc: "最大行数"]
    ]

  @impl true
  def run(params, _context) do
    path = Path.expand(params.file_path)

    case File.read(path) do
      {:ok, content} ->
        max = Map.get(params, :max_lines, 100)
        result = Gong.Truncate.truncate(content, :head, max_lines: max)

        {:ok,
         %{
           file_path: path,
           content: result.content,
           truncated: result.truncated,
           total_lines: result.total_lines
         }}

      {:error, reason} ->
        {:error, "读取文件失败: #{path} (#{reason})"}
    end
  end
end
