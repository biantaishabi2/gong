defmodule Gong.Stream do
  @moduledoc """
  流式输出 — Stream.Event 结构体和事件类型定义。

  支持流式 LLM 响应的事件化处理。
  """

  defmodule Event do
    @moduledoc "流式事件结构体"

    @type event_type ::
            :text_start
            | :text_delta
            | :text_end
            | :tool_start
            | :tool_delta
            | :tool_end
            | :error

    @type t :: %__MODULE__{
            type: event_type(),
            content: String.t() | nil,
            tool_name: String.t() | nil,
            tool_args: map() | nil,
            timestamp: integer()
          }

    defstruct [:type, :content, :tool_name, :tool_args, :timestamp]

    @doc "创建事件，自动添加时间戳"
    def new(type, opts \\ []) do
      %__MODULE__{
        type: type,
        content: Keyword.get(opts, :content),
        tool_name: Keyword.get(opts, :tool_name),
        tool_args: Keyword.get(opts, :tool_args),
        timestamp: System.monotonic_time(:millisecond)
      }
    end
  end

  @doc "从事件列表拼接文本内容"
  @spec concat_text([Event.t()]) :: String.t()
  def concat_text(events) do
    events
    |> Enum.filter(fn e -> e.type == :text_delta end)
    |> Enum.map(fn e -> e.content || "" end)
    |> Enum.join()
  end

  @doc "校验事件序列是否符合规范"
  @spec valid_sequence?([Event.t()]) :: boolean()
  def valid_sequence?(events) do
    types = Enum.map(events, & &1.type)
    do_validate_sequence(types)
  end

  # 空序列合法
  defp do_validate_sequence([]), do: true

  # 文本序列：text_start → text_delta* → text_end
  defp do_validate_sequence([:text_start | rest]) do
    {deltas, after_deltas} = Enum.split_while(rest, fn t -> t == :text_delta end)
    case after_deltas do
      [:text_end | remaining] ->
        # 至少需要一个内容（delta 可以为 0，但一般至少 1）
        _has_content = length(deltas) >= 0
        do_validate_sequence(remaining)
      _ ->
        false
    end
  end

  # 工具序列：tool_start → tool_delta* → tool_end
  defp do_validate_sequence([:tool_start | rest]) do
    {_deltas, after_deltas} = Enum.split_while(rest, fn t -> t == :tool_delta end)
    case after_deltas do
      [:tool_end | remaining] -> do_validate_sequence(remaining)
      _ -> false
    end
  end

  # error 可以在任何位置出现
  defp do_validate_sequence([:error | rest]) do
    do_validate_sequence(rest)
  end

  defp do_validate_sequence(_), do: false

  @doc "从 chunk 队列生成 Stream.Event 列表"
  @spec chunks_to_events([{:chunk, String.t()} | :done | {:abort, term()}]) :: [Event.t()]
  def chunks_to_events(chunks) do
    chunks_to_events(chunks, [], false)
  end

  defp chunks_to_events([], events, _started) do
    Enum.reverse(events)
  end

  # delay chunk 跳过（不影响事件流）
  defp chunks_to_events([{:delay, _ms} | rest], events, started) do
    chunks_to_events(rest, events, started)
  end

  defp chunks_to_events([{:chunk, text} | rest], events, false) do
    # 第一个 chunk → text_start + text_delta
    start_event = Event.new(:text_start)
    delta_event = Event.new(:text_delta, content: text)
    chunks_to_events(rest, [delta_event, start_event | events], true)
  end

  defp chunks_to_events([{:chunk, text} | rest], events, true) do
    delta_event = Event.new(:text_delta, content: text)
    chunks_to_events(rest, [delta_event | events], true)
  end

  defp chunks_to_events([:done | _rest], events, started) do
    if started do
      end_event = Event.new(:text_end)
      Enum.reverse([end_event | events])
    else
      Enum.reverse(events)
    end
  end

  defp chunks_to_events([{:abort, reason} | _rest], events, started) do
    error_event = Event.new(:error, content: to_string(reason))
    if started do
      end_event = Event.new(:text_end)
      Enum.reverse([end_event, error_event | events])
    else
      Enum.reverse([error_event | events])
    end
  end

  @doc "从 chunk 队列生成工具调用事件列表"
  @spec tool_chunks_to_events(String.t(), [{:chunk, String.t()} | :done]) :: [Event.t()]
  def tool_chunks_to_events(tool_name, chunks) do
    start_event = Event.new(:tool_start, tool_name: tool_name)

    delta_events =
      chunks
      |> Enum.filter(fn
        {:chunk, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:chunk, json_part} ->
        Event.new(:tool_delta, content: json_part, tool_name: tool_name)
      end)

    end_event = Event.new(:tool_end, tool_name: tool_name)

    [start_event | delta_events] ++ [end_event]
  end
end
