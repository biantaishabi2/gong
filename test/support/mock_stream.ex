defmodule Gong.MockStream do
  @moduledoc """
  MockStream — 模拟流式 LLM 响应。

  接受 chunk 队列，按顺序生成 Stream.Event 事件。
  支持文本流、工具调用流、中断和超时模拟。
  """

  alias Gong.Stream
  alias Gong.Stream.Event

  @doc "执行流式模拟，返回事件列表和拼接后的文本"
  @spec run(list()) :: {[Event.t()], String.t()}
  def run(chunk_queue) do
    events = Stream.chunks_to_events(chunk_queue)
    text = Stream.concat_text(events)
    {events, text}
  end

  @doc "执行带超时检查的流式模拟"
  @spec run_with_timeout(list(), non_neg_integer()) :: {[Event.t()], String.t()} | {:error, :timeout}
  def run_with_timeout(chunk_queue, timeout_ms) do
    task = Task.async(fn ->
      run_with_delays(chunk_queue)
    end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  @doc "执行带延迟的流式模拟（用于超时测试）"
  @spec run_with_delays(list()) :: {[Event.t()], String.t()}
  def run_with_delays(chunk_queue) do
    events = process_chunks_with_delays(chunk_queue)
    text = Stream.concat_text(events)
    {events, text}
  end

  defp process_chunks_with_delays(chunks) do
    process_chunks_with_delays(chunks, [], false)
  end

  defp process_chunks_with_delays([], events, _started) do
    Enum.reverse(events)
  end

  defp process_chunks_with_delays([{:delay, ms} | rest], events, started) do
    Process.sleep(ms)
    process_chunks_with_delays(rest, events, started)
  end

  defp process_chunks_with_delays([{:chunk, text} | rest], events, false) do
    start_event = Event.new(:text_start)
    delta_event = Event.new(:text_delta, content: text)
    process_chunks_with_delays(rest, [delta_event, start_event | events], true)
  end

  defp process_chunks_with_delays([{:chunk, text} | rest], events, true) do
    delta_event = Event.new(:text_delta, content: text)
    process_chunks_with_delays(rest, [delta_event | events], true)
  end

  defp process_chunks_with_delays([:done | _rest], events, started) do
    if started do
      end_event = Event.new(:text_end)
      Enum.reverse([end_event | events])
    else
      Enum.reverse(events)
    end
  end

  defp process_chunks_with_delays([{:abort, reason} | _rest], events, started) do
    error_event = Event.new(:error, content: to_string(reason))
    if started do
      end_event = Event.new(:text_end)
      Enum.reverse([end_event, error_event | events])
    else
      Enum.reverse([error_event | events])
    end
  end

  @doc "生成工具调用流式事件"
  @spec tool_stream(String.t(), list()) :: [Event.t()]
  def tool_stream(tool_name, json_chunks) do
    Stream.tool_chunks_to_events(tool_name, json_chunks)
  end
end
