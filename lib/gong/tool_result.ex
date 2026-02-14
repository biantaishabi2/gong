defmodule Gong.ToolResult do
  @moduledoc """
  工具结果双通道 — 分离 LLM 内容和 UI 渲染数据。

  content: 发给 LLM 的精简文本
  details: 给 UI 渲染的结构化数据（可选）
  is_error: 是否为错误结果
  """

  @type t :: %__MODULE__{
          content: String.t(),
          details: map() | nil,
          is_error: boolean()
        }

  defstruct [:content, :details, is_error: false]

  @doc "从纯文本构造，兼容旧格式。details 为 nil。"
  def from_text(text) when is_binary(text) do
    %__MODULE__{content: text, details: nil, is_error: false}
  end

  @doc "构造带 details 的完整结果"
  def new(content, details \\ nil, is_error \\ false) do
    %__MODULE__{content: content, details: details, is_error: is_error}
  end

  @doc "构造错误结果"
  def error(content, details \\ nil) do
    %__MODULE__{content: content, details: details, is_error: true}
  end

  @doc "获取发给 LLM 的内容"
  def llm_content(%__MODULE__{content: content}), do: content

  @doc "获取 UI 渲染数据"
  def ui_details(%__MODULE__{details: details}), do: details

  @doc "是否为错误结果"
  def error?(%__MODULE__{is_error: is_error}), do: is_error
end
