defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。

  逐行流式渲染，表格整体渲染：普通行（标题、段落、列表等）逐行即时输出，
  表格行攒起来，表格结束时 prescan 列宽后一次性渲染（保证对齐）。
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
      completed: 0,
      in_code_block: false,
      pending_cols: 0,
      prefix_written: false,
      table_buffer: []
    })
  end

  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    state = Process.get(:gong_stream, default_state())

    # 首个 delta 到达时写前缀
    state =
      if not state.prefix_written do
        IO.write("#{@blue}#{@prefix}#{@reset}")
        %{state | prefix_written: true, pending_cols: Md.display_width(@prefix)}
      else
        state
      end

    new_buffer = state.buffer <> content

    # 分割成完成的行 + 未完成的尾部
    parts = String.split(new_buffer, "\n")
    {complete_lines, [pending]} = Enum.split(parts, length(parts) - 1)
    new_complete_count = length(complete_lines)
    prev_complete = state.completed

    state =
      if new_complete_count > prev_complete do
        new_lines = Enum.slice(complete_lines, prev_complete, new_complete_count - prev_complete)

        # 擦除当前未完成行
        erase = build_erase(state.pending_cols)

        # 逐行处理，区分表格和非表格
        {state_after, rendered_output} =
          Enum.reduce(new_lines, {state, []}, fn line, {st, output} ->
            process_line(line, st, output)
          end)

        # 前缀
        prefix_part = if prev_complete == 0, do: "#{@blue}#{@prefix}#{@reset}", else: ""

        rendered_str = Enum.join(rendered_output, "\n")
        trailing = if rendered_output != [], do: "\n", else: ""

        IO.write([erase, prefix_part, rendered_str, trailing, pending])

        %{state_after |
          buffer: new_buffer,
          completed: new_complete_count,
          pending_cols: Md.display_width(pending),
          prefix_written: true
        }
      else
        IO.write(content)
        %{state |
          buffer: new_buffer,
          pending_cols: state.pending_cols + Md.display_width(content)
        }
      end

    Process.put(:gong_stream, state)
  end

  def render(%Events{type: "message.end"}) do
    state = Process.get(:gong_stream, default_state())
    Process.delete(:gong_stream)

    if not state.prefix_written do
      :ok
    else
      # 刷出未闭合的表格缓冲
      if state.table_buffer != [] do
        erase = build_erase(state.pending_cols)
        IO.write(erase)
        rendered = flush_table_buffer(state.table_buffer, state.in_code_block)
        IO.write(rendered <> "\n")
      else
        # 处理最后一个未完成行
        parts = String.split(state.buffer, "\n")
        pending_line = List.last(parts) || ""

        if pending_line != "" do
          case Md.render_line(pending_line, state.in_code_block) do
            {:buffered, _} -> :ok
            {rendered, _} ->
              erase = build_erase(state.pending_cols)
              prefix_part = if state.completed == 0, do: "#{@blue}#{@prefix}#{@reset}", else: ""
              IO.write([erase, prefix_part, rendered, "\n"])
          end
        else
          IO.write("\n")
        end
      end

      Md.flush_table_bottom()
    end
  end

  def render(%Events{type: "tool.start", payload: payload}) do
    tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name") || "unknown"
    tool_args = Map.get(payload, :tool_args) || Map.get(payload, "tool_args") || %{}
    args_str = Gong.CLI.ToolDisplay.format(tool_name, tool_args)

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

  # 处理单行：表格行攒缓冲，非表格行直接渲染（先刷表格缓冲）
  defp process_line(line, state, output) do
    is_table = is_table_line?(line)
    in_code = state.in_code_block
    is_fence = String.starts_with?(String.trim_leading(line), "```")

    cond do
      # 代码块边界
      is_fence ->
        # 先刷表格缓冲
        {state, output} = maybe_flush_table(state, output)
        case Md.render_line(line, in_code) do
          {:buffered, true} -> {%{state | in_code_block: true}, output}
          {rendered, new_in_code} -> {%{state | in_code_block: new_in_code}, output ++ [rendered]}
        end

      # 代码块内
      in_code ->
        case Md.render_line(line, true) do
          {:buffered, true} -> {state, output}
          {rendered, new_in_code} -> {%{state | in_code_block: new_in_code}, output ++ [rendered]}
        end

      # 表格行 → 攒缓冲
      is_table ->
        {%{state | table_buffer: state.table_buffer ++ [line]}, output}

      # 非表格行 → 先刷表格缓冲，再渲染本行
      true ->
        {state, output} = maybe_flush_table(state, output)
        case Md.render_line(line, false) do
          {:buffered, _} -> {state, output}
          {rendered, _} -> {state, output ++ [rendered]}
        end
    end
  end

  defp is_table_line?(line) do
    Regex.match?(~r/^\|.+\|$/, line) or Regex.match?(~r/^\|[\s\-:|]+\|$/, line)
  end

  # 如果有表格缓冲，prescan + 渲染后追加到 output
  defp maybe_flush_table(%{table_buffer: []} = state, output), do: {state, output}
  defp maybe_flush_table(state, output) do
    rendered = flush_table_buffer(state.table_buffer, false)
    {%{state | table_buffer: []}, output ++ [rendered]}
  end

  # 对缓冲的表格行做 prescan 列宽后渲染
  defp flush_table_buffer(lines, in_code) do
    # prescan 列宽
    widths = prescan_widths(lines)
    if widths != [], do: Process.put(:gong_md_table_widths, widths)

    {rendered, _} =
      Enum.reduce(lines, {[], in_code}, fn line, {acc, ic} ->
        case Md.render_line(line, ic) do
          {:buffered, true} -> {acc, true}
          {rendered, new_ic} -> {acc ++ [rendered], new_ic}
        end
      end)

    # 表格底边框
    trailing =
      if Process.get(:gong_md_in_table, false) do
        Process.put(:gong_md_in_table, false)
        w = Process.get(:gong_md_table_widths, [])
        Process.delete(:gong_md_table_widths)
        "\n" <> build_table_border(w, "└", "┴", "┘")
      else
        ""
      end

    Enum.join(rendered, "\n") <> trailing
  end

  # 预扫描表格数据行列宽
  defp prescan_widths(lines) do
    lines
    |> Enum.filter(fn line ->
      Regex.match?(~r/^\|.+\|$/, line) and not Regex.match?(~r/^\|[\s\-:|]+\|$/, line)
    end)
    |> Enum.reduce([], fn line, acc ->
      widths =
        line
        |> String.trim_leading("|")
        |> String.trim_trailing("|")
        |> String.split("|")
        |> Enum.map(fn cell ->
          cell |> String.trim() |> Md.display_width()
        end)
      merge_widths(widths, acc)
    end)
  end

  defp merge_widths(new, []), do: new
  defp merge_widths(new, prev) do
    max_len = max(length(new), length(prev))
    nw = new ++ List.duplicate(0, max_len - length(new))
    pw = prev ++ List.duplicate(0, max_len - length(prev))
    Enum.zip(nw, pw) |> Enum.map(fn {a, b} -> max(a, b) end)
  end

  # 构建表格边框行
  defp build_table_border(col_widths, left, mid, right) do
    segs = Enum.map(col_widths, fn w -> String.duplicate("─", w + 2) end)
    inner = Enum.join(segs, mid)
    "  #{@faint}#{left}#{inner}#{right}#{@reset}"
  end

  defp default_state do
    %{buffer: "", completed: 0, in_code_block: false, pending_cols: 0, prefix_written: false, table_buffer: []}
  end

  defp build_erase(pending_cols) do
    width = Md.terminal_width()
    rows = max(1, ceil(pending_cols / max(width, 1)))
    if rows > 1, do: "\e[#{rows - 1}A\r\e[J", else: "\r\e[J"
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
