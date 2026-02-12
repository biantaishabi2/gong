defmodule Gong.Tools.Ls do
  @moduledoc """
  目录列表 Action。

  列出指定目录的内容，包括文件大小、修改时间等元信息。
  """

  use Jido.Action,
    name: "list_directory",
    description: "列出目录内容",
    schema: [
      path: [type: :string, required: true, doc: "目录路径"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现目录列表逻辑
    {:ok, %{path: params.path, entries: []}}
  end
end
