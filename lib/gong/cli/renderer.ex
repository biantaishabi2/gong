defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。

  AI 回复采用「流式预览 + 完成重排」策略：
  delta 阶段输出原文让用户看到进度，message.end 时擦除原文，
  用 Md.render_inline 一次性渲染完整 Markdown（表格列宽对齐等）。
  """

  alias Gong.Session.Events
  alias Gong.CLI.Md

  @max_tool_args_length 80

  @blue IO.ANSI.blue()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @red IO.ANSI.red()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @prefix "◆ "

  @spec render(Events.t()) :: :ok

  def render(%Events{type: "message.start"}) do
    Process.put(:gong_stream, %{
      buffer: "",
      display_lines: 0,
      prefix_written: false
    })
  end

  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    state = Process.get(:gong_stream, %{buffer: "", display_lines: 0, prefix_written: false})

    # 首个 delta 到达时写前缀
    state =
      if not state.prefix_written do
        IO.write("#{@blue}#{@prefix}#{@reset}")
        %{state | prefix_written: true}
      else
        state
      end

    # 攒 buffer，同时输出原文让用户看到进度
    IO.write(content)
    new_buffer = state.buffer <> content

    # 跟踪已显示的终端行数（用于 message.end 时擦除）
    width = Md.terminal_width()
    wrap_lines =
      (@prefix <> new_buffer)
      |> String.split("\n")
      |> Enum.map(fn line -> max(1, ceil(Md.display_width(line) / max(width, 1))) end)
      |> Enum.sum()

    Process.put(:gong_stream, %{state | buffer: new_buffer, display_lines: wrap_lines})
  end

  def render(%Events{type: "message.end"}) do
    state = Process.get(:gong_stream, %{buffer: "", display_lines: 0, prefix_written: false})
    Process.delete(:gong_stream)

    # 空 message 静默跳过
    if not state.prefix_written do
      :ok
    else
      # 擦除所有已显示的原文
      erase = build_erase_lines(state.display_lines)
      IO.write(erase)

      # 用 render_inline 一次性渲染完整 Markdown
      rendered = Md.render_inline(state.buffer)
      IO.write("#{@blue}#{@prefix}#{@reset}#{rendered}\n")
    end
  end

  def render(%Events{type: "tool.start", payload: payload}) do
    tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name") || "unknown"
    tool_args = Map.get(payload, :tool_args) || Map.get(payload, "tool_args") || %{}
    args_str = Gong.CLI.ToolDisplay.format(tool_name, tool_args)

    # 不换行，等 tool.end 追加状态标记
    IO.write("#{@yellow}⚡ #{tool_name}#{@reset} #{@faint}#{truncate(args_str, @max_tool_args_length)}#{@reset}")
  end

  def render(%Events{type: "tool.end", payload: payload}) do
    success = Map.get(payload, :success, Map.get(payload, "success", true))

    if success do
      IO.puts(" #{@green}✓#{@reset}")
    else
      IO.puts(" #{@red}✗#{@reset}")
    end
  end

  def render(%Events{type: type, payload: payload, error: error}) when type in ["error.stream", "error.runtime"] do
    message =
      Map.get(payload, :message) || Map.get(payload, "message") ||
        get_in_error(payload) ||
        extract_error_message(error) ||
        "未知错误"

    IO.puts(:stderr, "#{@red}✗ #{message}#{@reset}")
  end

  def render(%Events{}) do
    :ok
  end

  # 擦除 n 行终端输出
  defp build_erase_lines(lines) when lines <= 1, do: "\r\e[J"
  defp build_erase_lines(lines) do
    "\e[#{lines - 1}A\r\e[J"
  end

  defp get_in_error(payload) do
    error = Map.get(payload, :error) || Map.get(payload, "error")
    if is_map(error), do: Map.get(error, :message) || Map.get(error, "message")
  end

  defp extract_error_message(nil), do: nil
  defp extract_error_message(error) when is_map(error) do
    Map.get(error, :message) || Map.get(error, "message")
  end
  defp extract_error_message(_), do: nil

  @doc "截断字符串到指定最大长度"
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(str, max) when byte_size(str) <= max, do: str

  def truncate(str, max) do
    String.slice(str, 0, max) <> "..."
  end
end
