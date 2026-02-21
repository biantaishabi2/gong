defmodule Gong.CLI.Md do
  @moduledoc """
  Markdown ANSI 渲染 — 纯自研，不依赖 IO.ANSI.Docs。

  流式阶段：`render_inline/1` 对完整 buffer 做格式替换，
  renderer 通过 diff flushed 长度只输出新增部分。
  """

  @bold IO.ANSI.bright()
  @cyan IO.ANSI.cyan()
  @yellow IO.ANSI.yellow()
  @underline IO.ANSI.underline()
  @faint IO.ANSI.faint()
  @reset IO.ANSI.reset()

  @doc """
  对 Markdown 文本做 ANSI 渲染，返回带格式的字符串。
  """
  @spec render_inline(String.t()) :: String.t()
  def render_inline(text) do
    {chunks, code_blocks} = extract_code_blocks(text)

    chunks
    |> Enum.map(fn
      {:text, t} -> render_text(t)
      {:code_block, idx} -> render_code_block(Enum.at(code_blocks, idx))
    end)
    |> Enum.join()
  end

  @doc "获取终端宽度，fallback 80"
  @spec terminal_width() :: pos_integer()
  def terminal_width do
    case :io.columns() do
      {:ok, cols} when cols > 0 -> cols
      _ -> 80
    end
  end

  @doc "计算文本在终端中占用的显示行数"
  @spec count_display_lines(String.t(), pos_integer()) :: non_neg_integer()
  def count_display_lines(text, width) do
    text
    |> strip_ansi()
    |> String.split("\n")
    |> Enum.map(fn line ->
      w = display_column_width(line)
      max(1, ceil(w / width))
    end)
    |> Enum.sum()
  end

  # --- 内部 ---

  # 提取围栏代码块保护（支持未闭合的代码块 — 流式场景）
  defp extract_code_blocks(text) do
    # 匹配已闭合和未闭合的代码块
    regex = ~r/(```[^\n]*\n(?:.*?```|.*))/s
    parts = Regex.split(regex, text, include_captures: true)

    {chunks, blocks, _idx} =
      Enum.reduce(parts, {[], [], 0}, fn part, {chunks, blocks, idx} ->
        if Regex.match?(~r/\A```/, part) do
          {chunks ++ [{:code_block, idx}], blocks ++ [part], idx + 1}
        else
          {chunks ++ [{:text, part}], blocks, idx}
        end
      end)

    {chunks, blocks}
  end

  # 渲染围栏代码块 — 青色缩进，去掉 ``` 行
  defp render_code_block(block) do
    lines = String.split(block, "\n")

    rendered =
      lines
      |> Enum.map(fn line ->
        if String.starts_with?(line, "```") do
          nil
        else
          "  #{@cyan}#{line}#{@reset}"
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    "\n#{rendered}\n"
  end

  # 渲染非代码块文本：逐行处理
  defp render_text(text) do
    text
    |> String.split("\n")
    |> Enum.map(&render_line/1)
    |> Enum.join("\n")
  end

  defp render_line(line) do
    cond do
      # 标题：1-6 个 # + 空格
      Regex.match?(~r/^\#{1,6}\s+/, line) ->
        heading = Regex.replace(~r/^\#{1,6}\s+/, line, "")
        "#{@bold}#{@yellow}#{do_inline(heading)}#{@reset}"

      # 无序列表
      match_list_unordered?(line) ->
        [_, indent, content] = Regex.run(~r/^(\s*)[-*+]\s+(.*)$/, line)
        "#{indent}  • #{do_inline(content)}"

      # 有序列表
      match_list_ordered?(line) ->
        [_, indent, num, content] = Regex.run(~r/^(\s*)(\d+)\.\s+(.*)$/, line)
        "#{indent}  #{num}. #{do_inline(content)}"

      # 引用
      String.starts_with?(line, ">") ->
        content = String.replace_prefix(line, "> ", "") |> String.replace_prefix(">", "")
        "#{@faint}│ #{do_inline(content)}#{@reset}"

      # 水平线
      Regex.match?(~r/^---+$/, line) ->
        "#{@faint}────────#{@reset}"

      # 普通行
      true ->
        do_inline(line)
    end
  end

  defp match_list_unordered?(line), do: Regex.match?(~r/^(\s*)[-*+]\s+/, line)
  defp match_list_ordered?(line), do: Regex.match?(~r/^(\s*)\d+\.\s+/, line)

  # 行内格式替换
  defp do_inline(text) do
    text
    |> replace_inline_code()
    |> replace_bold()
    |> replace_italic()
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
