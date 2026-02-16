defmodule Gong.Compaction.Summarizer do
  @moduledoc """
  LLM 摘要实现。

  调用 Gong.Prompt.build_summarize_prompt/1 构建 prompt，
  通过 ReqLLM 调用 LLM 生成对话摘要，供 Compaction 使用。
  """

  @doc """
  对消息列表生成 LLM 摘要。

  返回 `{:ok, summary_text}` 或 `{:error, reason}`。
  """
  @spec summarize([map()]) :: {:ok, String.t()} | {:error, term()}
  def summarize(messages) do
    {_type, prompt_text} = Gong.Prompt.build_summarize_prompt(messages)
    model = Gong.ModelRegistry.current_model_string()

    request_messages = [
      %{role: "system", content: "你是摘要助手，负责将对话历史压缩为结构化摘要。"},
      %{role: "user", content: prompt_text}
    ]

    case ReqLLM.generate_text(model, request_messages, receive_timeout: 30_000) do
      {:ok, response} ->
        text = ReqLLM.Response.text(response)
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
