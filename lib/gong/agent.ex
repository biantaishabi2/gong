defmodule Gong.Agent do
  @moduledoc """
  Gong 编码 Agent — 基于 Jido.AI.ReActAgent 的 LLM + 工具循环。

  通过 `ask/2,3`、`await/1,2`、`ask_sync/2,3` 与 Agent 交互。
  ReAct 策略内置 LLM 调用 + 工具执行的状态机循环。
  """

  use Jido.AI.ReActAgent,
    name: "gong",
    description: "Gong 通用编码 Agent",
    tools: [
      Gong.Tools.Read,
      Gong.Tools.Write,
      Gong.Tools.Edit,
      Gong.Tools.Bash,
      Gong.Tools.Grep,
      Gong.Tools.Find,
      Gong.Tools.Ls
    ],
    model: "anthropic:claude-sonnet-4-5-20250929",
    max_iterations: 25,
    system_prompt: "你是 Gong，一个通用编码 Agent。使用提供的工具完成用户任务。优先使用专用工具而非 bash。文件路径使用绝对路径。回复简洁，中文。"
end
