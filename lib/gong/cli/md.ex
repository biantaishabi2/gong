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

      # 表格分隔线（|---|---|）— 渲染为横线
      Regex.match?(~r/^\|[\s\-:|]+\|$/, line) ->
        {"  #{@faint}#{String.duplicate("─", 40)}#{@reset}", false}

      # 表格数据行（| cell | cell |）
      Regex.match?(~r/^\|.+\|$/, line) ->
        cells =
          line
          |> String.trim_leading("|")
          |> String.trim_trailing("|")
          |> String.split("|")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&do_inline/1)

        {"  #{Enum.join(cells, "#{@faint}  │  #{@reset}")}", false}

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
    {lines, _in_code} =
      text
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {acc, in_code} ->
        {rendered, new_in_code} = render_line(line, in_code)
        {acc ++ [rendered], new_in_code}
      end)

    Enum.join(lines, "\n")
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
