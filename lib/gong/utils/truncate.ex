defmodule Gong.Utils.Truncate do
  @moduledoc """
  通用文本截断工具。

  三种策略：
  - `:head` — 保留开头，截断尾部（支持 max_lines + max_bytes 双限制）
  - `:tail` — 保留尾部，截断开头（支持 max_lines + max_bytes 双限制）
  - `:head_tail` — 保留头尾，截断中间（先按行数裁剪，再按字节数二次限制）

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

    @type t :: %__MODULE__{
            content: String.t(),
            truncated: boolean(),
            truncated_by: :lines | :bytes | :chars | [:lines | :bytes] | nil,
            total_lines: non_neg_integer(),
            total_bytes: non_neg_integer(),
            output_lines: non_neg_integer(),
            output_bytes: non_neg_integer(),
            last_line_partial: boolean(),
            first_line_exceeds_limit: boolean(),
            max_lines: non_neg_integer() | nil,
            max_bytes: non_neg_integer() | nil
          }
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

  # ── Head+Tail 截断：保留头尾，截断中间 ──

  @default_head_lines 50
  @default_tail_lines 50

  @doc """
  头尾保留截断：保留开头和结尾，截断中间部分。

  执行顺序：先按行数裁剪（默认头50行+尾50行），再按字节数二次限制（默认30KB）。
  单行超长场景按字节头尾各保留一半。

  ## 选项

  - `:head_lines` - 保留头部行数（默认 50）
  - `:tail_lines` - 保留尾部行数（默认 50）
  - `:max_bytes` - 最大字节数（默认 30000）
  """
  @spec truncate_head_tail(String.t(), keyword()) :: %Result{}
  def truncate_head_tail(content, opts \\ []) do
    head_lines = max(Keyword.get(opts, :head_lines, @default_head_lines), 0)
    tail_lines = max(Keyword.get(opts, :tail_lines, @default_tail_lines), 0)
    max_bytes = max(Keyword.get(opts, :max_bytes, @default_max_bytes), 0)

    total_bytes = byte_size(content)
    # 处理末尾换行：split 后去除尾部空元素，避免多算一行
    raw_lines = String.split(content, "\n")

    {lines, has_trailing_newline} =
      if content != "" and String.ends_with?(content, "\n") do
        {List.delete_at(raw_lines, -1), true}
      else
        {raw_lines, false}
      end

    total_line_count = length(lines)

    within_lines = total_line_count <= head_lines + tail_lines
    within_bytes = total_bytes <= max_bytes

    if within_lines and within_bytes do
      # 不需要截断
      %Result{
        content: content,
        truncated: false,
        total_lines: total_line_count,
        total_bytes: total_bytes,
        output_lines: total_line_count,
        output_bytes: total_bytes,
        max_bytes: max_bytes
      }
    else
      do_truncate_head_tail(lines, head_lines, tail_lines, max_bytes, total_line_count, total_bytes, has_trailing_newline)
    end
  end

  defp do_truncate_head_tail(lines, head_lines, tail_lines, max_bytes, total_line_count, total_bytes, has_trailing_newline) do
    # 末尾换行后缀：截断时不保留，不截断的路径由调用方原样返回
    trailing = if has_trailing_newline, do: "\n", else: ""

    cond do
      # 单行超长 → 按字节头尾各保留一半
      total_line_count == 1 ->
        truncate_single_line_bytes(hd(lines), max_bytes, total_bytes)

      # 行数超限 → 先按行截断
      total_line_count > head_lines + tail_lines ->
        head_part = Enum.take(lines, head_lines)
        tail_part = Enum.take(lines, -tail_lines)
        omitted_lines = total_line_count - head_lines - tail_lines
        omitted_content = lines |> Enum.drop(head_lines) |> Enum.take(omitted_lines) |> Enum.join("\n")
        omitted_bytes = byte_size(omitted_content)

        marker = "... [省略 #{omitted_lines} 行, 共 #{omitted_bytes} 字节] ..."
        joined = Enum.join(head_part, "\n") <> "\n" <> marker <> "\n" <> Enum.join(tail_part, "\n") <> trailing

        if byte_size(joined) > max_bytes do
          # 二次字节截断
          result_content = truncate_bytes_head_tail(joined, max_bytes)
          %Result{
            content: result_content,
            truncated: true,
            truncated_by: [:lines, :bytes],
            total_lines: total_line_count,
            total_bytes: total_bytes,
            output_lines: head_lines + tail_lines + 1,
            output_bytes: byte_size(result_content),
            max_bytes: max_bytes
          }
        else
          %Result{
            content: joined,
            truncated: true,
            truncated_by: :lines,
            total_lines: total_line_count,
            total_bytes: total_bytes,
            output_lines: head_lines + tail_lines + 1,
            output_bytes: byte_size(joined),
            max_bytes: max_bytes
          }
        end

      # 行数未超但字节超限 → 按字节头尾截断
      true ->
        original = Enum.join(lines, "\n") <> trailing
        result_content = truncate_bytes_head_tail(original, max_bytes)
        %Result{
          content: result_content,
          truncated: true,
          truncated_by: :bytes,
          total_lines: total_line_count,
          total_bytes: total_bytes,
          output_lines: total_line_count,
          output_bytes: byte_size(result_content),
          max_bytes: max_bytes
        }
    end
  end

  # 单行超长：按字节头尾各保留一半，确保结果 <= max_bytes
  defp truncate_single_line_bytes(line, max_bytes, total_bytes) do
    result_content = do_bytes_head_tail(line, max_bytes)

    %Result{
      content: result_content,
      truncated: true,
      truncated_by: :bytes,
      total_lines: 1,
      total_bytes: total_bytes,
      output_lines: length(String.split(result_content, "\n")),
      output_bytes: byte_size(result_content),
      max_bytes: max_bytes
    }
  end

  # 按字节头尾截断拼接后的文本，确保结果 <= max_bytes
  defp truncate_bytes_head_tail(text, max_bytes) do
    do_bytes_head_tail(text, max_bytes)
  end

  # 通用字节头尾截断：确保结果严格 <= max_bytes
  defp do_bytes_head_tail(text, max_bytes) do
    total = byte_size(text)
    # 使用最大可能的省略值（= total）计算 marker 大小上限，确保结果不超限
    worst_marker = "... [省略 约#{total} 字节] ..."
    # marker 加两个换行分隔符的总开销
    marker_overhead = byte_size(worst_marker) + 2

    if max_bytes <= marker_overhead do
      # max_bytes 太小，无法容纳内容 + marker，只返回标注
      worst_marker
    else
      available = max_bytes - marker_overhead
      half = div(available, 2)
      head_part = safe_binary_slice(text, 0, half)
      tail_part = safe_binary_tail(text, half)
      omitted = total - byte_size(head_part) - byte_size(tail_part)
      marker = "... [省略 约#{omitted} 字节] ..."
      # 因为 omitted <= total，所以 byte_size(marker) <= byte_size(worst_marker)
      # 因此 byte_size(result) <= available + marker_overhead = max_bytes
      head_part <> "\n" <> marker <> "\n" <> tail_part
    end
  end

  # UTF-8 安全的头部字节切片
  defp safe_binary_slice(binary, start, len) do
    raw = binary_part(binary, start, min(len, byte_size(binary) - start))
    # 截断尾部可能的不完整 UTF-8 字符
    trim_trailing_incomplete_utf8(raw)
  end

  # UTF-8 安全的尾部字节切片
  defp safe_binary_tail(binary, len) do
    total = byte_size(binary)
    start = max(total - len, 0)
    raw = binary_part(binary, start, total - start)
    skip_leading_continuation(raw)
  end

  # 去掉尾部不完整的 UTF-8 字节
  defp trim_trailing_incomplete_utf8(<<>>), do: <<>>

  defp trim_trailing_incomplete_utf8(binary) do
    size = byte_size(binary)
    # 检查最后1-3个字节是否是不完整的多字节序列起始
    do_trim_trailing(binary, size)
  end

  defp do_trim_trailing(binary, size) when size <= 0, do: binary

  defp do_trim_trailing(binary, size) do
    # 从末尾往回找，检查是否有不完整的 UTF-8 序列
    case String.valid?(binary) do
      true -> binary
      false ->
        # 逐字节缩减直到有效
        binary_part(binary, 0, size - 1) |> do_trim_trailing(size - 1)
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
      do_truncate_head(
        lines,
        effective_max_lines,
        max_bytes,
        total_line_count,
        total_bytes,
        max_lines
      )
    end
  end

  defp do_truncate_head(
         lines,
         effective_max_lines,
         max_bytes,
         total_line_count,
         total_bytes,
         orig_max_lines
       ) do
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
      do_truncate_tail(
        lines,
        effective_max_lines,
        max_bytes,
        total_line_count,
        total_bytes,
        max_lines
      )
    end
  end

  defp do_truncate_tail(
         lines,
         effective_max_lines,
         max_bytes,
         total_line_count,
         total_bytes,
         orig_max_lines
       ) do
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

          {[partial_line | kept], count + 1, bytes + separator + byte_size(partial_line), :bytes,
           true}
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
