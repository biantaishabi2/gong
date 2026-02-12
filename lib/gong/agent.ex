defmodule Gong.Agent do
  @moduledoc """
  Jido Agent 定义。

  持有工具集（Actions）、系统提示词和运行状态。
  通过 `Jido.Agent` 宏定义，运行时由 `Jido.Agent.Server` GenServer 驱动。
  """

  use Jido.Agent,
    name: "gong",
    description: "通用 Agent 引擎",
    actions: [
      Gong.Tools.Read,
      Gong.Tools.Write,
      Gong.Tools.Edit,
      Gong.Tools.Bash,
      Gong.Tools.Grep,
      Gong.Tools.Find,
      Gong.Tools.Ls
    ],
    schema: [
      workspace: [type: :string, required: true, doc: "工作目录路径"],
      system_prompt: [type: :string, default: "", doc: "系统提示词"]
    ]
end
