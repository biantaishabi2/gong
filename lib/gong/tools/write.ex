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
    # TODO: 实现文件写入逻辑
    {:ok, %{file_path: params.file_path, bytes_written: 0}}
  end
end
