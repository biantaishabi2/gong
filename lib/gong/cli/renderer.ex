defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。

  AI 回复：流式阶段原样输出，message.end 擦除重渲染 Markdown。
  工具调用/错误用颜色区分。
  """

  alias Gong.Session.Events
  alias Gong.CLI.Md

  @max_tool_args_length 80
  @max_result_length 200

  @blue IO.ANSI.blue()
  @yellow IO.ANSI.yellow()
  @cyan IO.ANSI.cyan()
  @red IO.ANSI.red()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @prefix "◆ "

  @spec render(Events.t()) :: :ok

  def render(%Events{type: "message.start"}) do
    Process.put(:gong_stream_buffer, "")
    IO.write("#{@blue}#{@prefix}#{@reset}")
  end

  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    IO.write(content)
    buffer = Process.get(:gong_stream_buffer, "")
    Process.put(:gong_stream_buffer, buffer <> content)
  end

  def render(%Events{type: "message.end"}) do
    buffer = Process.get(:gong_stream_buffer, "")
    Process.delete(:gong_stream_buffer)

    if buffer != "" do
      # 擦除已输出的纯文本（含前缀行），重渲染带格式版本
      width = Md.terminal_width()
      raw_output = @prefix <> buffer
      lines = Md.count_display_lines(raw_output, width)

      # 构建完整的擦除+重绘序列，一次性写入避免 buffer 分裂
      erase =
        if lines > 1 do
          "\r\e[#{lines - 1}A\e[J"
        else
          "\r\e[J"
        end

      rendered = Md.render_inline(buffer)
      IO.write([erase, @blue, @prefix, @reset, rendered, "\n"])
    else
      IO.write("\n")
    end
  end

  def render(%Events{type: "tool.start", payload: payload}) do
    tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name") || "unknown"
    tool_args = Map.get(payload, :tool_args) || Map.get(payload, "tool_args") || %{}

    args_str =
      case tool_args do
        s when is_binary(s) -> s
        m when is_map(m) -> Jason.encode!(m)
        other -> inspect(other)
      end

    IO.puts("#{@yellow}⚡ #{tool_name}#{@reset} #{@faint}#{truncate(args_str, @max_tool_args_length)}#{@reset}")
  end

  def render(%Events{type: "tool.end", payload: payload}) do
    result = Map.get(payload, :result) || Map.get(payload, "result") || ""

    result_str =
      case result do
        s when is_binary(s) -> s
        other -> inspect(other)
      end

    IO.puts("#{@cyan}✓ #{truncate(result_str, @max_result_length)}#{@reset}")
  end

  def render(%Events{type: type, payload: payload}) when type in ["error.stream", "error.runtime"] do
    message =
      Map.get(payload, :message) || Map.get(payload, "message") ||
        get_in_error(payload) || "未知错误"

    IO.puts(:stderr, "#{@red}✗ #{message}#{@reset}")
  end

  def render(%Events{}) do
    :ok
  end

  defp get_in_error(payload) do
    error = Map.get(payload, :error) || Map.get(payload, "error")
    if is_map(error), do: Map.get(error, :message) || Map.get(error, "message")
  end

  @doc "截断字符串到指定最大长度"
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(str, max) when byte_size(str) <= max, do: str

  def truncate(str, max) do
    String.slice(str, 0, max) <> "..."
  end
end
