defmodule Gong.Tools.Edit do
  @moduledoc """
  文件编辑 Action。

  精确字符串替换，支持唯一性校验和多次替换模式。
  """

  use Jido.Action,
    name: "edit_file",
    description: "替换文件中的指定文本",
    schema: [
      file_path: [type: :string, required: true, doc: "文件绝对路径"],
      old_string: [type: :string, required: true, doc: "要替换的文本"],
      new_string: [type: :string, required: true, doc: "替换后的文本"],
      replace_all: [type: :boolean, default: false, doc: "是否替换所有匹配"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现编辑逻辑
    {:ok, %{file_path: params.file_path, replacements: 0}}
  end
end
