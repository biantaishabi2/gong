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

  # ── Compaction 结构化摘要 ──

  @doc """
  构建压缩摘要 prompt。

  自动检测消息中是否包含前次摘要（`[会话摘要]` 前缀），
  有则返回 {:update, prompt}，无则返回 {:create, prompt}。
  """
  @spec build_summarize_prompt([map()]) :: {:create | :update, String.t()}
  def build_summarize_prompt(messages) do
    file_ops = extract_file_operations(messages)
    conversation = format_conversation(messages)

    case find_previous_summary(messages) do
      nil ->
        {:create, compaction_prompt(conversation, file_ops)}

      prev_summary ->
        {:update, compaction_update_prompt(conversation, file_ops, prev_summary)}
    end
  end

  @doc "从 tool_call 消息中提取文件操作列表"
  @spec extract_file_operations([map()]) :: String.t()
  def extract_file_operations(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      tool_calls = Map.get(msg, :tool_calls) || Map.get(msg, "tool_calls") || []

      Enum.map(tool_calls, fn tc ->
        name = tc[:name] || tc["name"]
        args = tc[:arguments] || tc["arguments"] || %{}
        path = args["file_path"] || args[:file_path] || args["path"] || args[:path]
        if path, do: "#{name}: #{path}", else: nil
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "（无文件操作）"
      ops -> Enum.join(ops, "\n")
    end
  end

  @doc "组装完整系统提示词（base + context + skills + 时间 + cwd）"
  @spec full_system_prompt(keyword()) :: String.t()
  def full_system_prompt(opts \\ []) do
    workspace = Keyword.get(opts, :workspace, ".")
    context = Keyword.get(opts, :context, "")
    skills = Keyword.get(opts, :skills, "")

    now = DateTime.utc_now() |> DateTime.to_string()

    parts = [
      @default_prompt,
      if(context != "", do: "\n## Context\n#{context}\n", else: ""),
      if(skills != "", do: "\n## Skills\n#{skills}\n", else: ""),
      "\n当前时间：#{now}",
      "\n当前工作目录：#{workspace}\n"
    ]

    Enum.join(parts)
  end

  # ── 内部实现 ──

  defp compaction_prompt(conversation, file_ops) do
    """
    请将以下对话历史压缩为结构化摘要。保留关键信息，删除冗余内容。

    ## 输出格式

    **Goal**: 用户的主要目标
    **Constraints**: 重要限制条件
    **Progress**:
    - Done: 已完成的步骤
    - In Progress: 进行中的步骤
    - Blocked: 被阻塞的步骤
    **Key Decisions**: 重要决策
    **Next Steps**: 下一步计划
    **Critical Context**: 不可丢失的上下文信息

    ## 文件操作汇总
    #{file_ops}

    ## 对话历史
    #{conversation}
    """
  end

  defp compaction_update_prompt(conversation, file_ops, previous_summary) do
    """
    请基于已有摘要，结合新对话内容，更新结构化摘要。输出格式不变。

    ## 已有摘要
    #{previous_summary}

    ## 新对话内容
    #{conversation}

    ## 文件操作汇总
    #{file_ops}
    """
  end

  defp find_previous_summary(messages) do
    Enum.find_value(messages, fn msg ->
      content = Map.get(msg, :content) || Map.get(msg, "content") || ""
      content_str = to_string(content)

      if String.starts_with?(content_str, "[会话摘要]") do
        String.trim_leading(content_str, "[会话摘要] ")
      end
    end)
  end

  defp format_conversation(messages) do
    messages
    |> Enum.map(fn msg ->
      role = Map.get(msg, :role) || Map.get(msg, "role") || "unknown"
      content = Map.get(msg, :content) || Map.get(msg, "content") || ""
      "[#{role}] #{String.slice(to_string(content), 0, 500)}"
    end)
    |> Enum.join("\n")
  end
end
