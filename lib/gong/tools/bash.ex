defmodule Gong.Tools.Bash do
  @moduledoc """
  命令执行 Action。

  通过 `System.cmd/3` 或 Port 执行 shell 命令，
  支持超时控制、输出截断、工作目录设置。
  """

  use Jido.Action,
    name: "bash",
    description: "执行 shell 命令",
    schema: [
      command: [type: :string, required: true, doc: "要执行的命令"],
      timeout: [type: :non_neg_integer, default: 120_000, doc: "超时毫秒数"],
      working_dir: [type: :string, doc: "工作目录"]
    ]

  @impl true
  def run(params, _context) do
    # TODO: 实现命令执行逻辑
    {:ok, %{command: params.command, exit_code: 0, stdout: "", stderr: ""}}
  end
end
