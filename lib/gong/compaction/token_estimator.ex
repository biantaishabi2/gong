defmodule Gong.Compaction.TokenEstimator do
  @moduledoc """
  Token 估算模块。

  用于估算中英文混合文本的 token 数量，无外部依赖。
  规则：
  - CJK 表意字符: 1字 ≈ 2 tokens
  - 英文单词: 1 word ≈ 1.3 tokens
  - ASCII 标点/特殊字符: 每个 0.5 token（BPE 常与相邻字符合并）
  - 中文标点: 每个 1 token
  - 换行符: 每个 1 token
  - 空格: 仅作为单词分隔符，不单独计 token
  """

  @doc "估算单段文本的 token 数"
  @spec estimate(String.t()) :: non_neg_integer()
  def estimate(nil), do: 0
  def estimate(""), do: 0

  def estimate(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> count_tokens(0, :start)
    |> round()
    |> max(0)
  end

  # 遍历 graphemes 分类计数
  defp count_tokens([], acc, :in_word), do: acc + 1.3
  defp count_tokens([], acc, _state), do: acc

  defp count_tokens([char | rest], acc, state) do
    cond do
      cjk?(char) ->
        # CJK 表意字符：每个约 2 tokens
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 2, :start)

      ascii_letter?(char) ->
        # 英文字母/数字：积累单词
        count_tokens(rest, acc, :in_word)

      cjk_punct?(char) ->
        # 中文标点：每个 1 token
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 1, :start)

      carriage_return?(char) ->
        # \r：跳过，避免 CRLF 重复计数
        count_tokens(rest, acc, state)

      newline?(char) ->
        # 换行符：BPE 中常与缩进合并，每个约 0.5 token
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 0.5, :start)

      space?(char) ->
        # 空格：仅作为单词分隔符，结算前一个单词，不单独计 token
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus, :start)

      ascii_punct?(char) ->
        # ASCII 标点：BPE 中常与相邻字符合并，每个约 0.5 token
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 0.5, :start)

      true ->
        # 其他字符（emoji 等）：每个 1 token
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 1, :start)
    end
  end

  # CJK 统一表意文字（不含标点）
  defp cjk?(<<cp::utf8>>) do
    (cp >= 0x4E00 and cp <= 0x9FFF) or
      (cp >= 0x3400 and cp <= 0x4DBF) or
      (cp >= 0x20000 and cp <= 0x2A6DF)
  end

  defp cjk?(_), do: false

  # 中文标点范围
  defp cjk_punct?(<<cp::utf8>>) do
    (cp >= 0x3000 and cp <= 0x303F) or
      (cp >= 0xFF00 and cp <= 0xFFEF)
  end

  defp cjk_punct?(_), do: false

  defp ascii_letter?(<<cp::utf8>>) do
    (cp >= ?a and cp <= ?z) or (cp >= ?A and cp <= ?Z) or
      (cp >= ?0 and cp <= ?9)
  end

  defp ascii_letter?(_), do: false

  # ASCII 标点和运算符
  defp ascii_punct?(<<cp::utf8>>) do
    cp in [
      ?{, ?}, ?[, ?], ?(, ?), ?:, ?;, ?,, ?., ?<, ?>, ?+, ?-, ?*, ?/,
      ?=, ?!, ?@, ?#, ?$, ?%, ?^, ?&, ?|, ?~, ?", ?', ??, ?\\, ?`, ?_
    ]
  end

  defp ascii_punct?(_), do: false

  defp carriage_return?("\r"), do: true
  defp carriage_return?(_), do: false

  defp newline?("\r\n"), do: true
  defp newline?("\n"), do: true
  defp newline?(_), do: false

  defp space?(" "), do: true
  defp space?("\t"), do: true
  defp space?(_), do: false

  @doc "估算消息列表的总 token 数"
  @spec estimate_messages([map()]) :: non_neg_integer()
  def estimate_messages([]), do: 0

  def estimate_messages(messages) when is_list(messages) do
    messages
    |> Enum.reduce(0, fn msg, acc ->
      content = extract_content(msg)
      acc + estimate(content)
    end)
  end

  defp extract_content(%{content: content}) when is_binary(content), do: content
  defp extract_content(%{"content" => content}) when is_binary(content), do: content
  defp extract_content(_), do: ""
end
