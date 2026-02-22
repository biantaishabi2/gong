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
    {type, prompt_text} = Gong.Prompt.build_summarize_prompt(messages)

    # 从 ModelRegistry 获取完整 model config，走 LLMRouter 统一路由
    model_config =
      case Gong.ModelRegistry.current_model() do
        {_name, config} -> config
        nil -> %{provider: "deepseek", model_id: "deepseek-chat", api_key_env: "DEEPSEEK_API_KEY"}
      end

    system_content =
      case type do
        :create -> "你是摘要助手，负责将对话历史压缩为结构化摘要。"
        :update -> "你是摘要助手，负责基于已有摘要和新对话内容更新结构化摘要。保留已有摘要中仍然相关的信息。"
      end

    request_messages = [
      %{role: "system", content: system_content},
      %{role: "user", content: prompt_text}
    ]

    case Gong.LLMRouter.generate_text(model_config, request_messages, receive_timeout: 30_000) do
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
