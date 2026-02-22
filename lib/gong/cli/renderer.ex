defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。

  AI 回复逐行流式渲染：每完成一行（遇到 \\n），擦除当前未完成行原文，
  重新输出 Markdown 格式化版本。追踪 pending 文本的显示列数，
  当 raw 文本在终端折行时用 \\e[nA 回退多行再擦除。
  """

  alias Gong.Session.Events
  alias Gong.CLI.Md

  @max_tool_args_length 80

  @blue IO.ANSI.blue()
  @yellow IO.ANSI.yellow()
  @cyan IO.ANSI.cyan()
  @red IO.ANSI.red()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @prefix "◆ "

  @spec render(Events.t()) :: :ok

  def render(%Events{type: "message.start"}) do
    # pending_cols: 当前未完成行在终端上占的显示列数（用于折行擦除）
    Process.put(:gong_stream, %{
      buffer: "",
      completed: 0,
      in_code_block: false,
      pending_cols: Md.display_width(@prefix)
    })

    IO.write("#{@blue}#{@prefix}#{@reset}")
  end

  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    state = Process.get(:gong_stream, %{buffer: "", completed: 0, in_code_block: false, pending_cols: 0})
    new_buffer = state.buffer <> content

    # 分割成完成的行 + 未完成的尾部
    parts = String.split(new_buffer, "\n")
    {complete_lines, [pending]} = Enum.split(parts, length(parts) - 1)
    new_complete_count = length(complete_lines)
    prev_complete = state.completed

    if new_complete_count > prev_complete do
      # 有新的完成行，擦除当前未完成行，渲染新完成的行
      new_lines = Enum.slice(complete_lines, prev_complete, new_complete_count - prev_complete)

      # 擦除：根据 pending 文本占用的终端行数决定是否需要回退多行
      erase = build_erase(state.pending_cols)

      # 渲染每一行
      {rendered_lines, in_code} =
        Enum.reduce(new_lines, {[], state.in_code_block}, fn line, {acc, in_code} ->
          {rendered, new_in_code} = Md.render_line(line, in_code)
          {acc ++ [rendered], new_in_code}
        end)

      output = Enum.join(rendered_lines, "\n") <> "\n"

      # 前缀：第一行需要加 ◆（如果是首批完成行）
      prefix_part =
        if prev_complete == 0 do
          "#{@blue}#{@prefix}#{@reset}"
        else
          ""
        end

      IO.write([erase, prefix_part, output, pending])

      Process.put(:gong_stream, %{
        buffer: new_buffer,
        completed: new_complete_count,
        in_code_block: in_code,
        pending_cols: Md.display_width(pending)
      })
    else
      # 没有新行完成，直接写原文
      IO.write(content)
      Process.put(:gong_stream, %{state | buffer: new_buffer, pending_cols: state.pending_cols + Md.display_width(content)})
    end
  end

  def render(%Events{type: "message.end"}) do
    state = Process.get(:gong_stream, %{buffer: "", completed: 0, in_code_block: false, pending_cols: 0})
    Process.delete(:gong_stream)

    # 处理最后一个未完成行
    parts = String.split(state.buffer, "\n")
    pending = List.last(parts) || ""

    if pending != "" do
      {rendered, _} = Md.render_line(pending, state.in_code_block)

      erase = build_erase(state.pending_cols)

      # 第一行需要前缀
      prefix_part =
        if state.completed == 0 do
          "#{@blue}#{@prefix}#{@reset}"
        else
          ""
        end

      IO.write([erase, prefix_part, rendered, "\n"])
    else
      IO.write("\n")
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
      IO.puts(" #{@cyan}✓#{@reset}")
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

  # 构建擦除序列：pending_cols 超过终端宽度时回退多行
  defp build_erase(pending_cols) do
    width = Md.terminal_width()
    rows = max(1, ceil(pending_cols / max(width, 1)))

    if rows > 1 do
      "\e[#{rows - 1}A\r\e[J"
    else
      "\r\e[J"
    end
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
