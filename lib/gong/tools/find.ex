defmodule Gong.Tools.Find do
  @moduledoc """
  文件查找 Action。

  通过 glob 模式查找文件，支持排除模式和结果限制。
  """

  use Jido.Action,
    name: "find_files",
    description: "按 glob 模式查找文件",
    schema: [
      pattern: [type: :string, required: true, doc: "glob 模式"],
      path: [type: :string, default: ".", doc: "搜索根路径"],
      exclude: [type: :string, doc: "排除模式"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现查找逻辑
    {:ok, %{pattern: params.pattern, files: []}}
  end
end
