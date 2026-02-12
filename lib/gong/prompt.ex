defmodule Gong.Prompt do
  @moduledoc "系统提示词模块"

  @default_prompt """
  你是 Gong，一个通用编码 Agent。
  使用提供的工具（read_file, write_file, edit_file, bash, grep, find_files, list_directory）完成用户任务。
  优先使用专用工具而非 bash。
  文件路径使用绝对路径。
  回复简洁，中文。
  """

  @spec default_system_prompt() :: String.t()
  def default_system_prompt, do: @default_prompt

  @spec system_prompt(String.t()) :: String.t()
  def system_prompt(workspace) do
    @default_prompt <> "当前工作目录：#{workspace}\n"
  end
end
