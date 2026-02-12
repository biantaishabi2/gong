defmodule Gong.Truncate do
  @moduledoc """
  输出截断系统。

  三种策略：
  - `:head` — 保留开头，截断尾部
  - `:tail` — 保留尾部，截断开头
  - `:line` — 按行截断，保留头尾各 N 行

  所有截断操作都保证 UTF-8 边界安全。
  """

  @default_max_bytes 30_000
  @default_keep_lines 50

  @type strategy :: :head | :tail | :line

  @doc "按策略截断文本，返回 {截断后文本, 是否被截断}"
  @spec truncate(String.t(), strategy(), keyword()) :: {String.t(), boolean()}
  def truncate(text, strategy \\ :tail, opts \\ [])

  def truncate(text, :head, opts) do
    max = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_head(text, max)
  end

  def truncate(text, :tail, opts) do
    max = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_tail(text, max)
  end

  def truncate(text, :line, opts) do
    keep = Keyword.get(opts, :keep_lines, @default_keep_lines)
    truncate_line(text, keep)
  end

  defp truncate_head(text, max) when byte_size(text) <= max, do: {text, false}

  defp truncate_head(text, max) do
    kept = safe_binary_part(text, 0, max)
    marker = "\n... [截断：保留前 #{byte_size(kept)} 字节，原始 #{byte_size(text)} 字节]"
    {kept <> marker, true}
  end

  defp truncate_tail(text, max) when byte_size(text) <= max, do: {text, false}

  defp truncate_tail(text, max) do
    start = byte_size(text) - max
    kept = safe_binary_part(text, start, max)
    marker = "[截断：保留后 #{byte_size(kept)} 字节，原始 #{byte_size(text)} 字节] ...\n"
    {marker <> kept, true}
  end

  defp truncate_line(text, keep) do
    lines = String.split(text, ~r/\r?\n/)
    total = length(lines)

    if total <= keep * 2 do
      {text, false}
    else
      head = Enum.take(lines, keep)
      tail = Enum.take(lines, -keep)
      omitted = total - keep * 2
      marker = "\n... [省略 #{omitted} 行] ...\n"
      {Enum.join(head, "\n") <> marker <> Enum.join(tail, "\n"), true}
    end
  end

  # UTF-8 安全的 binary_part — 避免截断在多字节字符中间
  defp safe_binary_part(binary, start, len) do
    raw = binary_part(binary, start, min(len, byte_size(binary) - start))
    # 去掉尾部不完整的 UTF-8 序列
    trim_incomplete_utf8(raw)
  end

  defp trim_incomplete_utf8(<<>>), do: <<>>

  defp trim_incomplete_utf8(binary) do
    case String.valid?(binary) do
      true ->
        binary

      false ->
        # 从末尾逐字节回退，直到找到合法的 UTF-8 序列
        size = byte_size(binary) - 1
        trim_incomplete_utf8(binary_part(binary, 0, size))
    end
  end
end
