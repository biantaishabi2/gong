defmodule Gong.CLI.Md do
  @moduledoc """
  Markdown ANSI 渲染 — 逐行渲染，追踪代码块状态。
  """

  @bold IO.ANSI.bright()
  @cyan IO.ANSI.cyan()
  @yellow IO.ANSI.yellow()
  @underline IO.ANSI.underline()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @doc """
  渲染单行 Markdown，返回 {rendered_string, new_in_code_block}。

  `in_code_block` 追踪是否在围栏代码块内。
  """
  @spec render_line(String.t(), boolean()) :: {String.t(), boolean()}
  def render_line(line, in_code_block) do
    # 检测是否离开表格，输出底边框
    is_table_line = Regex.match?(~r/^\|.+\|$/, line) or Regex.match?(~r/^\|[\s\-:|]+\|$/, line)
    table_bottom =
      if Process.get(:gong_md_in_table, false) and not is_table_line do
        Process.put(:gong_md_in_table, false)
        col_widths = Process.get(:gong_md_table_widths, [])
        Process.delete(:gong_md_table_widths)
        bottom = build_table_border(col_widths, "└", "┴", "┘")
        "#{bottom}\n"
      else
        ""
      end

    {rendered, new_in_code} = do_render_line(line, in_code_block)
    {table_bottom <> rendered, new_in_code}
  end

  defp do_render_line(line, in_code_block) do
    cond do
      # 围栏代码块边界
      String.starts_with?(String.trim_leading(line), "```") ->
        if in_code_block do
          # 关闭代码块，不输出 ``` 行
          {"", false}
        else
          # 打开代码块，不输出 ``` 行
          {"", true}
        end

      # 代码块内部 — 青色缩进
      in_code_block ->
        {"  #{@cyan}#{line}#{@reset}", true}

      # 标题
      Regex.match?(~r/^\#{1,6}\s+/, line) ->
        heading = Regex.replace(~r/^\#{1,6}\s+/, line, "")
        {"#{@bold}#{@yellow}#{do_inline(heading)}#{@reset}", false}

      # 无序列表
      Regex.match?(~r/^(\s*)[-*+]\s+/, line) ->
        [_, indent, content] = Regex.run(~r/^(\s*)[-*+]\s+(.*)$/, line)
        {"#{indent}  • #{do_inline(content)}", false}

      # 有序列表
      Regex.match?(~r/^(\s*)\d+\.\s+/, line) ->
        [_, indent, num, content] = Regex.run(~r/^(\s*)(\d+)\.\s+(.*)$/, line)
        {"#{indent}  #{num}. #{do_inline(content)}", false}

      # 引用
      String.starts_with?(line, ">") ->
        content = String.replace_prefix(line, "> ", "") |> String.replace_prefix(">", "")
        {"#{@faint}│ #{do_inline(content)}#{@reset}", false}

      # 表格分隔线（|---|---|）— 渲染为横线边框，用已记录的列宽
      Regex.match?(~r/^\|[\s\-:|]+\|$/, line) ->
        col_widths = Process.get(:gong_md_table_widths, [])
        col_widths =
          if col_widths == [] do
            col_count = line |> String.split("|") |> length() |> Kernel.-(2)
            List.duplicate(10, col_count)
          else
            col_widths
          end
        {build_table_border(col_widths, "├", "┼", "┤"), false}

      # 表格数据行（| cell | cell |）
      Regex.match?(~r/^\|.+\|$/, line) ->
        cells =
          line
          |> String.trim_leading("|")
          |> String.trim_trailing("|")
          |> String.split("|")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&do_inline/1)

        # 计算每列显示宽度，更新已记录的最大列宽
        cell_widths = Enum.map(cells, fn c -> c |> strip_ansi() |> display_column_width() end)
        prev_widths = Process.get(:gong_md_table_widths, [])
        col_widths = merge_col_widths(cell_widths, prev_widths)
        Process.put(:gong_md_table_widths, col_widths)

        padded = Enum.zip(cells, col_widths) |> Enum.map(fn {cell, w} -> pad_cell(cell, w) end)
        row = "  #{@faint}│#{@reset}#{Enum.join(padded, "#{@faint}│#{@reset}")}#{@faint}│#{@reset}"

        # 表格首行前加顶边框
        in_table = Process.get(:gong_md_in_table, false)
        col_count = length(cells)
        if not in_table do
          Process.put(:gong_md_in_table, true)
          Process.put(:gong_md_table_cols, col_count)
          top = build_table_border(col_widths, "┌", "┬", "┐")
          {"#{top}\n#{row}", false}
        else
          {row, false}
        end

      # 水平线
      Regex.match?(~r/^---+$/, line) ->
        {"#{@faint}────────#{@reset}", false}

      # 空行
      String.trim(line) == "" ->
        {"", false}

      # 普通行
      true ->
        {do_inline(line), false}
    end
  end

  @doc """
  对完整文本做 Markdown ANSI 渲染（非流式场景用）。
  """
  @spec render_inline(String.t()) :: String.t()
  def render_inline(text) do
    lines = String.split(text, "\n")

    # 第一遍：预扫描表格列宽
    col_widths = prescan_table_widths(lines)
    if col_widths != [] do
      Process.put(:gong_md_table_widths, col_widths)
    end

    {rendered_lines, _in_code} =
      Enum.reduce(lines, {[], false}, fn line, {acc, in_code} ->
        {rendered, new_in_code} = render_line(line, in_code)
        {acc ++ [rendered], new_in_code}
      end)

    # 文本结束时如果还在表格内，追加底边框
    trailing =
      if Process.get(:gong_md_in_table, false) do
        Process.put(:gong_md_in_table, false)
        widths = Process.get(:gong_md_table_widths, [])
        Process.delete(:gong_md_table_widths)
        "\n" <> build_table_border(widths, "└", "┴", "┘")
      else
        Process.delete(:gong_md_table_widths)
        ""
      end

    Enum.join(rendered_lines, "\n") <> trailing
  end

  @doc "获取终端宽度，fallback 80"
  @spec terminal_width() :: pos_integer()
  def terminal_width do
    case :io.columns() do
      {:ok, cols} when cols > 0 -> cols
      _ -> 80
    end
  end

  @doc "计算字符串的终端显示宽度（CJK 双宽，忽略 ANSI）"
  @spec display_width(String.t()) :: non_neg_integer()
  def display_width(str) do
    str |> strip_ansi() |> display_column_width()
  end

  @doc "计算文本在终端中占用的显示行数"
  @spec count_display_lines(String.t(), pos_integer()) :: non_neg_integer()
  def count_display_lines(text, width) do
    text
    |> String.split("\n")
    |> Enum.map(fn line ->
      w = display_width(line)
      max(1, ceil(w / width))
    end)
    |> Enum.sum()
  end

  # --- 行内格式 ---

  defp do_inline(text) do
    text
    |> replace_inline_code()
    |> replace_bold()
    |> replace_italic()
    |> replace_links()
    |> replace_urls()
    |> replace_file_paths()
  end

  defp replace_inline_code(text) do
    Regex.replace(~r/`([^`]+)`/, text, "#{@cyan}\\1#{@reset}")
  end

  defp replace_bold(text) do
    Regex.replace(~r/\*\*(.+?)\*\*/, text, "#{@bold}\\1#{@reset}")
  end

  defp replace_italic(text) do
    Regex.replace(~r/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, text, "#{@underline}\\1#{@reset}")
  end

  # Markdown 链接 [text](url) → 下划线文本 + 暗色 URL
  defp replace_links(text) do
    Regex.replace(~r/\[([^\]]+)\]\((https?:\/\/[^)]+)\)/, text, "#{@underline}\\1#{@reset} #{@faint}\\2#{@reset}")
  end

  # 裸 URL（未被其他格式包裹的）
  defp replace_urls(text) do
    Regex.replace(~r/(?<![(\w])https?:\/\/[^\s)<>]+/, text, "#{@underline}\\0#{@reset}")
  end

  # 文件路径（以 / 或 ~/ 开头，含 . 扩展名，排除 URL 内的路径）
  defp replace_file_paths(text) do
    Regex.replace(~r/(?<![:\/\w])[~]?\/[\w\-.\/@]+\.\w+/, text, "#{@underline}\\0#{@reset}")
  end

  # 预扫描表格数据行，计算所有列的最大显示宽度
  defp prescan_table_widths(lines) do
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
          cell |> String.trim() |> do_inline() |> strip_ansi() |> display_column_width()
        end)
      merge_col_widths(widths, acc)
    end)
  end

  # 合并列宽：取每列的最大值
  defp merge_col_widths(new_widths, []), do: new_widths
  defp merge_col_widths(new_widths, prev_widths) do
    max_len = max(length(new_widths), length(prev_widths))
    nw = new_widths ++ List.duplicate(0, max_len - length(new_widths))
    pw = prev_widths ++ List.duplicate(0, max_len - length(prev_widths))
    Enum.zip(nw, pw) |> Enum.map(fn {a, b} -> max(a, b) end)
  end

  # 构建表格边框行（顶/底）
  defp build_table_border(col_widths, left, mid, right) do
    segs = Enum.map(col_widths, fn w -> String.duplicate("─", w + 2) end)
    inner = Enum.join(segs, mid)
    "  #{@faint}#{left}#{inner}#{right}#{@reset}"
  end

  # 单元格填充到指定显示宽度
  defp pad_cell(text, width) do
    visible_width = text |> strip_ansi() |> display_column_width()
    padding = max(0, width - visible_width)
    " #{text}#{String.duplicate(" ", padding)} "
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*m/, text, "")
  end

  defp display_column_width(str) do
    str
    |> String.to_charlist()
    |> Enum.reduce(0, fn cp, acc ->
      acc + if cjk?(cp), do: 2, else: 1
    end)
  end

  defp cjk?(cp) when cp >= 0x4E00 and cp <= 0x9FFF, do: true
  defp cjk?(cp) when cp >= 0x3400 and cp <= 0x4DBF, do: true
  defp cjk?(cp) when cp >= 0x3000 and cp <= 0x303F, do: true
  defp cjk?(cp) when cp >= 0xFF00 and cp <= 0xFFEF, do: true
  defp cjk?(cp) when cp >= 0xF900 and cp <= 0xFAFF, do: true
  defp cjk?(cp) when cp >= 0x20000 and cp <= 0x2A6DF, do: true
  defp cjk?(_), do: false
end
