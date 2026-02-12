defmodule Gong.Truncate do
  @moduledoc """
  输出截断系统。

  两种策略：
  - `:head` — 保留开头，截断尾部（支持 max_lines + max_bytes 双限制）
  - `:tail` — 保留尾部，截断开头（支持 max_lines + max_bytes 双限制）

  单行截断：
  - `truncate_line/2` — 按字符数截断单行

  所有截断操作都保证 UTF-8 边界安全。
  """

  defmodule Result do
    @moduledoc "截断结果结构体"
    defstruct content: "",
              truncated: false,
              truncated_by: nil,
              total_lines: 0,
              total_bytes: 0,
              output_lines: 0,
              output_bytes: 0,
              last_line_partial: false,
              first_line_exceeds_limit: false,
              max_lines: nil,
              max_bytes: nil
  end

  @default_max_bytes 30_000

  @type strategy :: :head | :tail

  @doc "按策略截断文本，返回 %Result{}"
  @spec truncate(String.t(), strategy(), keyword()) :: %Result{}
  def truncate(text, strategy \\ :tail, opts \\ [])

  def truncate(text, :head, opts) do
    max_lines = Keyword.get(opts, :max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_head(text, max_lines, max_bytes)
  end

  def truncate(text, :tail, opts) do
    max_lines = Keyword.get(opts, :max_lines)
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    truncate_tail(text, max_lines, max_bytes)
  end

  @doc "单行截断：超过 max_chars 则截断并添加标记"
  @spec truncate_line(String.t(), non_neg_integer()) :: %Result{}
  def truncate_line(text, max_chars) do
    total_bytes = byte_size(text)

    if String.length(text) <= max_chars do
      %Result{
        content: text,
        truncated: false,
        total_lines: 1,
        total_bytes: total_bytes,
        output_lines: 1,
        output_bytes: total_bytes
      }
    else
      truncated = String.slice(text, 0, max_chars)
      content = truncated <> " ... [truncated]"

      %Result{
        content: content,
        truncated: true,
        truncated_by: :chars,
        total_lines: 1,
        total_bytes: total_bytes,
        output_lines: 1,
        output_bytes: byte_size(content)
      }
    end
  end

  # ── Head 截断：保留开头 ──

  defp truncate_head(text, max_lines, max_bytes) do
    total_bytes = byte_size(text)
    lines = String.split(text, "\n")
    total_line_count = length(lines)
    effective_max_lines = max_lines || total_line_count

    within_lines = total_line_count <= effective_max_lines
    within_bytes = total_bytes <= max_bytes

    if within_lines and within_bytes do
      %Result{
        content: text,
        truncated: false,
        total_lines: total_line_count,
        total_bytes: total_bytes,
        output_lines: total_line_count,
        output_bytes: total_bytes,
        max_lines: max_lines,
        max_bytes: max_bytes
      }
    else
      do_truncate_head(lines, effective_max_lines, max_bytes, total_line_count, total_bytes, max_lines)
    end
  end

  defp do_truncate_head(lines, effective_max_lines, max_bytes, total_line_count, total_bytes, orig_max_lines) do
    {kept, count, _bytes, truncated_by} =
      acc_head(lines, effective_max_lines, max_bytes, [], 0, 0)

    content = Enum.join(kept, "\n")
    first_exceeds = count == 0 and truncated_by == :bytes

    %Result{
      content: content,
      truncated: true,
      truncated_by: truncated_by,
      total_lines: total_line_count,
      total_bytes: total_bytes,
      output_lines: count,
      output_bytes: byte_size(content),
      first_line_exceeds_limit: first_exceeds,
      max_lines: orig_max_lines,
      max_bytes: max_bytes
    }
  end

  # 逐行累加，先触发的限制生效
  defp acc_head([], _max_lines, _max_bytes, kept, count, bytes) do
    {Enum.reverse(kept), count, bytes, nil}
  end

  defp acc_head([line | rest], max_lines, max_bytes, kept, count, bytes) do
    if count >= max_lines do
      {Enum.reverse(kept), count, bytes, :lines}
    else
      separator = if count == 0, do: 0, else: 1
      new_bytes = bytes + separator + byte_size(line)

      if new_bytes > max_bytes do
        if count == 0 do
          # 首行就超限
          {[], 0, 0, :bytes}
        else
          {Enum.reverse(kept), count, bytes, :bytes}
        end
      else
        acc_head(rest, max_lines, max_bytes, [line | kept], count + 1, new_bytes)
      end
    end
  end

  # ── Tail 截断：保留尾部 ──

  defp truncate_tail(text, max_lines, max_bytes) do
    total_bytes = byte_size(text)
    lines = String.split(text, "\n")
    total_line_count = length(lines)
    effective_max_lines = max_lines || total_line_count

    within_lines = total_line_count <= effective_max_lines
    within_bytes = total_bytes <= max_bytes

    if within_lines and within_bytes do
      %Result{
        content: text,
        truncated: false,
        total_lines: total_line_count,
        total_bytes: total_bytes,
        output_lines: total_line_count,
        output_bytes: total_bytes,
        max_lines: max_lines,
        max_bytes: max_bytes
      }
    else
      do_truncate_tail(lines, effective_max_lines, max_bytes, total_line_count, total_bytes, max_lines)
    end
  end

  defp do_truncate_tail(lines, effective_max_lines, max_bytes, total_line_count, total_bytes, orig_max_lines) do
    reversed = Enum.reverse(lines)

    {kept_rev, count, _bytes, truncated_by, partial} =
      acc_tail(reversed, effective_max_lines, max_bytes, [], 0, 0)

    content = kept_rev |> Enum.reverse() |> Enum.join("\n")

    %Result{
      content: content,
      truncated: true,
      truncated_by: truncated_by,
      total_lines: total_line_count,
      total_bytes: total_bytes,
      output_lines: count,
      output_bytes: byte_size(content),
      last_line_partial: partial,
      max_lines: orig_max_lines,
      max_bytes: max_bytes
    }
  end

  # 从末尾逐行收集
  defp acc_tail([], _max_lines, _max_bytes, kept, count, bytes) do
    {kept, count, bytes, nil, false}
  end

  defp acc_tail([line | rest], max_lines, max_bytes, kept, count, bytes) do
    if count >= max_lines do
      {kept, count, bytes, :lines, false}
    else
      separator = if count == 0, do: 0, else: 1
      line_bytes = byte_size(line)
      new_bytes = bytes + separator + line_bytes

      if new_bytes > max_bytes do
        # 尝试部分包含边界行
        remaining_budget = max_bytes - bytes - separator

        if remaining_budget > 0 do
          # 从行的末尾取 remaining_budget 字节（UTF-8 安全）
          start = max(line_bytes - remaining_budget, 0)
          partial_line = safe_tail_part(line, start, line_bytes - start)
          {[partial_line | kept], count + 1, bytes + separator + byte_size(partial_line), :bytes, true}
        else
          {kept, count, bytes, :bytes, false}
        end
      else
        acc_tail(rest, max_lines, max_bytes, [line | kept], count + 1, new_bytes)
      end
    end
  end

  # ── UTF-8 安全工具 ──

  # 从指定位置截取，并跳过开头的 UTF-8 continuation bytes
  defp safe_tail_part(binary, start, len) do
    raw = binary_part(binary, start, min(len, byte_size(binary) - start))
    skip_leading_continuation(raw)
  end

  # 跳过开头的 continuation bytes (10xxxxxx)，最多 3 个
  defp skip_leading_continuation(<<>>), do: <<>>

  defp skip_leading_continuation(binary) do
    do_skip_leading(binary, 0)
  end

  defp do_skip_leading(binary, skipped) when skipped >= 3, do: binary

  defp do_skip_leading(<<byte, rest::binary>>, skipped) when Bitwise.band(byte, 0xC0) == 0x80 do
    do_skip_leading(rest, skipped + 1)
  end

  defp do_skip_leading(binary, _skipped), do: binary
end
