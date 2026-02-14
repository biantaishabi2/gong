defmodule Gong.Compaction do
  @moduledoc """
  上下文压缩模块。

  当会话历史超过 token 预算时，对旧消息进行压缩：
  - 滑动窗口保留最近 N 条消息完整内容
  - 窗口外的消息由 LLM 生成摘要替代
  - 系统消息和 anchor 消息始终保留
  - LLM 摘要失败时回退到截断策略
  """

  alias Gong.Compaction.TokenEstimator

  @default_window_size 20
  @default_max_tokens 100_000
  @default_reserve_tokens 16_384
  @truncate_tool_max_chars 200

  @doc """
  压缩消息列表，返回 {压缩后消息, 摘要 | nil}。

  ## 选项

  - `:window_size` - 滑动窗口大小，保留最近 N 条非系统消息（默认 20）
  - `:max_tokens` - 最大 token 数阈值（默认 100_000）
  - `:context_window` - 上下文窗口总 token 数（设置后 max_tokens = context_window - reserve_tokens）
  - `:reserve_tokens` - 预留 token 数（默认 16_384，仅 context_window 模式生效）
  - `:summarize_fn` - 摘要函数 `(messages -> {:ok, summary} | {:error, reason})`
  """
  @spec compact([map()], keyword()) :: {[map()], String.t() | nil}
  def compact(messages, opts \\ []) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)
    max_tokens = resolve_max_tokens(opts)
    summarize_fn = Keyword.get(opts, :summarize_fn, &default_summarize/1)

    total = TokenEstimator.estimate_messages(messages)

    if total <= max_tokens do
      # 未超阈值，不需要压缩
      {messages, nil}
    else
      {old, recent} = split_with_system_preserved(messages, window_size)

      # 窗口足够大，无需压缩
      if old == [] do
        {messages, nil}
      else
        result =
          try do
          summarize_fn.(old)
        rescue
          _ -> {:error, :summarize_fn_crashed}
        end

      case result do
        {:ok, summary} ->
          summary_msg = %{role: "system", content: "[会话摘要] #{summary}"}
          {[summary_msg | recent], summary}

        {:error, _reason} ->
          # 回退：丢弃旧消息，保留窗口内 + 截断工具输出
          {truncate_tool_outputs(recent, max_tokens), nil}
      end
      end
    end
  end

  @doc """
  压缩并在 Tape 中创建 handoff anchor 记录摘要。

  返回 {压缩后消息, 摘要 | nil, 更新后的 tape_store}。
  """
  @spec compact_and_handoff(Gong.Tape.Store.t(), [map()], keyword()) ::
          {[map()], String.t() | nil, Gong.Tape.Store.t()}
  def compact_and_handoff(tape_store, messages, opts \\ []) do
    {compacted, summary} = compact(messages, opts)

    updated_store =
      if summary do
        case Gong.Tape.Store.handoff(tape_store, "compaction") do
          {:ok, _dir, store} ->
            case Gong.Tape.Store.append(store, "compaction", %{
                   kind: "compaction_summary",
                   content: summary
                 }) do
              {:ok, store2} -> store2
              {:error, _} -> store
            end

          {:error, _} ->
            tape_store
        end
      else
        tape_store
      end

    {compacted, summary, updated_store}
  end

  @doc """
  分割消息：系统消息始终保留在 recent 中，其余按窗口分割。

  返回 {old_messages, recent_messages}，其中 recent 包含所有系统消息 + 最近 window_size 条非系统消息。
  """
  @spec split_with_system_preserved([map()], non_neg_integer()) :: {[map()], [map()]}
  def split_with_system_preserved(messages, window_size) do
    {system_msgs, non_system} =
      Enum.split_with(messages, fn msg ->
        get_role(msg) == "system"
      end)

    if length(non_system) <= window_size do
      {[], system_msgs ++ non_system}
    else
      split_at = length(non_system) - window_size
      # 调整分割点，确保 tool_call/result 配对不被拆分
      safe_split = find_safe_boundary(non_system, split_at)
      {old, recent_non_system} = Enum.split(non_system, safe_split)
      {old, system_msgs ++ recent_non_system}
    end
  end

  # tool_call/result 配对保护 + session header 边界检查
  defp find_safe_boundary(_messages, split_at) when split_at <= 0, do: 0

  defp find_safe_boundary(messages, split_at) do
    if split_at >= length(messages) do
      split_at
    else
      # 检查 session header 边界：不越过带 [会话摘要] 标记的消息
      adjusted = check_session_header_boundary(messages, split_at)

      first_recent = Enum.at(messages, adjusted)

      cond do
        # recent 第一条是 tool result → 向前找到对应的 assistant(tool_calls)
        get_role(first_recent) == "tool" ->
          scan_back_for_tool_call_start(messages, adjusted)

        # old 最后一条是 assistant(tool_calls) → 它的 results 在 recent，把它也放进 recent
        adjusted > 0 and has_tool_calls?(Enum.at(messages, adjusted - 1)) ->
          adjusted - 1

        true ->
          adjusted
      end
    end
  end

  # session header 边界检查：如果 split_at 正好在 session header 之后，调整到 header 之前
  defp check_session_header_boundary(messages, split_at) do
    # 向后检查 split_at 附近是否有 session header（[会话摘要]）
    # 如果 old 区域最后一条是 session header，将其移入 recent
    if split_at > 0 do
      prev = Enum.at(messages, split_at - 1)
      content = get_content(prev) || ""

      if is_binary(content) and String.starts_with?(content, "[会话摘要]") do
        split_at - 1
      else
        split_at
      end
    else
      split_at
    end
  end

  # ── 溢出模型跟踪 ──

  @doc "设置触发 overflow 的模型（进程字典）"
  @spec set_overflow_model(String.t()) :: :ok
  def set_overflow_model(model) do
    Process.put(:gong_overflow_model, model)
    :ok
  end

  @doc "获取触发 overflow 的模型"
  @spec get_overflow_model() :: String.t() | nil
  def get_overflow_model do
    Process.get(:gong_overflow_model)
  end

  @doc "判断是否应该对当前模型执行压缩（溢出来自不同模型时返回 false）"
  @spec should_compact_for_model?(String.t()) :: boolean()
  def should_compact_for_model?(current_model) do
    case get_overflow_model() do
      nil -> true
      ^current_model -> true
      _other_model -> false
    end
  end

  defp scan_back_for_tool_call_start(_messages, idx) when idx <= 0, do: 0

  defp scan_back_for_tool_call_start(messages, idx) do
    prev = Enum.at(messages, idx - 1)

    cond do
      get_role(prev) == "tool" -> scan_back_for_tool_call_start(messages, idx - 1)
      has_tool_calls?(prev) -> idx - 1
      true -> idx
    end
  end

  defp has_tool_calls?(%{tool_calls: tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls?(%{"tool_calls" => tcs}) when is_list(tcs) and tcs != [], do: true
  defp has_tool_calls?(_), do: false

  @doc """
  回退策略：截断长工具输出以减少 token 数。
  """
  @spec truncate_tool_outputs([map()], non_neg_integer()) :: [map()]
  def truncate_tool_outputs(messages, _max_tokens) do
    Enum.map(messages, fn msg ->
      role = get_role(msg)

      if role == "tool" do
        content = get_content(msg)

        if is_binary(content) and String.length(content) > @truncate_tool_max_chars do
          truncated =
            String.slice(content, 0, @truncate_tool_max_chars) <>
              "\n...[输出已截断]"

          put_content(msg, truncated)
        else
          msg
        end
      else
        msg
      end
    end)
  end

  # 阈值计算：context_window 模式 vs 固定 max_tokens
  defp resolve_max_tokens(opts) do
    case Keyword.get(opts, :context_window) do
      nil ->
        Keyword.get(opts, :max_tokens, @default_max_tokens)

      ctx_window ->
        reserve = Keyword.get(opts, :reserve_tokens, @default_reserve_tokens)
        ctx_window - reserve
    end
  end

  # 默认摘要函数（占位，生产环境应注入 ReqLLM 调用）
  defp default_summarize(_messages) do
    {:error, :no_summarize_fn_configured}
  end

  defp get_role(%{role: role}), do: to_string(role)
  defp get_role(%{"role" => role}), do: to_string(role)
  defp get_role(_), do: nil

  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content
  defp get_content(_), do: nil

  defp put_content(%{content: _} = msg, new_content), do: %{msg | content: new_content}

  defp put_content(%{"content" => _} = msg, new_content),
    do: Map.put(msg, "content", new_content)

  defp put_content(msg, _), do: msg
end
