defmodule Gong.Compaction.TokenEstimator do
  @moduledoc """
  Token 估算模块。

  用于估算中英文混合文本的 token 数量，无外部依赖。
  规则：
  - 中文字符: 1字 ≈ 2 tokens
  - 英文单词: 1 word ≈ 1.3 tokens
  - 空白/标点: 不单独计 token
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
  # 中文字符每个 2 tokens
  # 连续英文字母序列视为单词，每个单词 1.3 tokens
  defp count_tokens([], acc, :in_word), do: acc + 1.3
  defp count_tokens([], acc, _state), do: acc

  defp count_tokens([char | rest], acc, state) do
    cond do
      cjk?(char) ->
        # 中文字符：每个约 2 tokens；如果之前在英文单词中，先结算
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus + 2, :start)

      ascii_letter?(char) ->
        # 英文字母：积累单词
        count_tokens(rest, acc, :in_word)

      true ->
        # 空白、标点等：如果之前在英文单词中，结算
        bonus = if state == :in_word, do: 1.3, else: 0
        count_tokens(rest, acc + bonus, :start)
    end
  end

  defp cjk?(<<cp::utf8>>) do
    # CJK 统一表意文字范围
    (cp >= 0x4E00 and cp <= 0x9FFF) or
      (cp >= 0x3400 and cp <= 0x4DBF) or
      (cp >= 0x20000 and cp <= 0x2A6DF) or
      # 中文标点
      (cp >= 0x3000 and cp <= 0x303F) or
      (cp >= 0xFF00 and cp <= 0xFFEF)
  end

  defp cjk?(_), do: false

  defp ascii_letter?(<<cp::utf8>>) do
    (cp >= ?a and cp <= ?z) or (cp >= ?A and cp <= ?Z) or
      (cp >= ?0 and cp <= ?9)
  end

  defp ascii_letter?(_), do: false

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
