defmodule Gong.Tools.Grep do
  @moduledoc """
  内容搜索 Action。

  基于正则表达式搜索文件内容，支持 glob 过滤、上下文行数、输出模式。
  """

  use Jido.Action,
    name: "grep",
    description: "搜索文件内容",
    schema: [
      pattern: [type: :string, required: true, doc: "正则表达式模式"],
      path: [type: :string, default: ".", doc: "搜索路径"],
      glob: [type: :string, doc: "文件 glob 过滤"],
      context: [type: :non_neg_integer, default: 0, doc: "上下文行数"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现搜索逻辑
    {:ok, %{pattern: params.pattern, matches: []}}
  end
end
