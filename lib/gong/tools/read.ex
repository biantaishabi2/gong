defmodule Gong.Tools.Read do
  @moduledoc """
  文件读取 Action。

  支持分页读取（offset + limit）、行号显示、UTF-8 长行截断。
  """

  use Jido.Action,
    name: "read_file",
    description: "读取文件内容，支持分页",
    schema: [
      file_path: [type: :string, required: true, doc: "文件绝对路径"],
      offset: [type: :non_neg_integer, default: 0, doc: "起始行号（0-based）"],
      limit: [type: :non_neg_integer, default: 2000, doc: "最多读取行数"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现文件读取逻辑
    {:ok, %{file_path: params.file_path, content: "", lines: 0}}
  end
end
