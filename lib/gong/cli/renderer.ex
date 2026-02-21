defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。

  AI 回复逐行流式渲染：每完成一行（遇到 \\n），擦除当前行原文，
  重新输出 Markdown 格式化版本。只擦一行（\\r\\e[J），无多行回退。
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
    # completed: 已渲染完的行数, in_code_block: 是否在围栏代码块内
    Process.put(:gong_stream, %{buffer: "", completed: 0, in_code_block: false})
    IO.write("#{@blue}#{@prefix}#{@reset}")
  end

  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    state = Process.get(:gong_stream, %{buffer: "", completed: 0, in_code_block: false})
    new_buffer = state.buffer <> content

    # 分割成完成的行 + 未完成的尾部
    parts = String.split(new_buffer, "\n")
    {complete_lines, [pending]} = Enum.split(parts, length(parts) - 1)
    new_complete_count = length(complete_lines)
    prev_complete = state.completed

    if new_complete_count > prev_complete do
      # 有新的完成行，擦除当前未完成行，渲染新完成的行
      new_lines = Enum.slice(complete_lines, prev_complete, new_complete_count - prev_complete)

      # 擦除当前行的原文
      erase = "\r\e[J"

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
        in_code_block: in_code
      })
    else
      # 没有新行完成，直接写原文
      IO.write(content)
      Process.put(:gong_stream, %{state | buffer: new_buffer})
    end
  end

  def render(%Events{type: "message.end"}) do
    state = Process.get(:gong_stream, %{buffer: "", completed: 0, in_code_block: false})
    Process.delete(:gong_stream)

    # 处理最后一个未完成行
    parts = String.split(state.buffer, "\n")
    pending = List.last(parts) || ""

    if pending != "" do
      {rendered, _} = Md.render_line(pending, state.in_code_block)

      # 第一行需要前缀
      prefix_part =
        if state.completed == 0 do
          "#{@blue}#{@prefix}#{@reset}"
        else
          ""
        end

      IO.write(["\r\e[J", prefix_part, rendered, "\n"])
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
