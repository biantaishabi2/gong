defmodule Gong.Tools.Edit do
  @moduledoc """
  文件编辑 Action。

  精确字符串替换，支持唯一性校验和多次替换模式。
  两层匹配策略：精确匹配 → 模糊匹配（5 步规范化）。
  """

  use Jido.Action,
    name: "edit_file",
    description: "替换文件中的指定文本",
    schema: [
      file_path: [type: :string, required: true, doc: "文件绝对路径"],
      old_string: [type: :string, required: true, doc: "要替换的文本"],
      new_string: [type: :string, required: true, doc: "替换后的文本"],
      replace_all: [type: :boolean, default: false, doc: "是否替换所有匹配"]
    ]

  @impl true
  def run(params, _context) do
    with {:ok, path} <- resolve_path(params.file_path),
         :ok <- check_readable(path),
         :ok <- validate_edit_params(params),
         {:ok, raw} <- File.read(path) do
      # BOM / CRLF 检测
      {content, bom} = strip_bom(raw)
      {normalized, line_ending} = detect_and_normalize_line_endings(content)

      # old_string / new_string 也规范化为 LF 做匹配
      old_str_lf = String.replace(params.old_string, "\r\n", "\n")
      new_str_lf = String.replace(params.new_string, "\r\n", "\n")

      with {:ok, edited, count} <- apply_edit(normalized, old_str_lf, new_str_lf, params[:replace_all] || false) do
        # 恢复原始行尾和 BOM
        restored = restore_line_endings(edited, line_ending)
        final = restore_bom(restored, bom)

        # 生成 diff
        diff = compute_diff(normalized, edited)

        case File.write(path, final) do
          :ok ->
            {:ok,
             %{
               file_path: path,
               replacements: count,
               diff: diff
             }}

          {:error, reason} ->
            {:error, "#{path}: Write failed (#{reason})"}
        end
      end
    end
  end

  # ── BOM 处理 ──

  @bom <<0xEF, 0xBB, 0xBF>>

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: {rest, @bom}
  defp strip_bom(content), do: {content, nil}

  defp restore_bom(content, nil), do: content
  defp restore_bom(content, bom), do: bom <> content

  # ── 行尾处理 ──

  defp detect_and_normalize_line_endings(content) do
    line_ending = if String.contains?(content, "\r\n"), do: :crlf, else: :lf
    normalized = String.replace(content, "\r\n", "\n")
    {normalized, line_ending}
  end

  defp restore_line_endings(content, :lf), do: content
  defp restore_line_endings(content, :crlf), do: String.replace(content, "\n", "\r\n")

  # ── Diff 生成 ──

  defp compute_diff(old_text, new_text) when old_text == new_text, do: nil

  defp compute_diff(old_text, new_text) do
    old_lines = String.split(old_text, "\n")
    new_lines = String.split(new_text, "\n")

    # 找到第一个不同的行
    first_changed =
      Enum.zip(old_lines, new_lines)
      |> Enum.find_index(fn {a, b} -> a != b end)
      |> Kernel.||(min(length(old_lines), length(new_lines)))

    # 生成上下文 diff（前后各 4 行）
    ctx_start = max(0, first_changed - 4)
    ctx_end_old = min(length(old_lines), first_changed + 4 + 1)
    ctx_end_new = min(length(new_lines), first_changed + 4 + 1)

    old_ctx = Enum.slice(old_lines, ctx_start, ctx_end_old - ctx_start)
    new_ctx = Enum.slice(new_lines, ctx_start, ctx_end_new - ctx_start)

    diff_lines =
      List.myers_difference(old_ctx, new_ctx)
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &(" " <> &1))
        {:del, lines} -> Enum.map(lines, &("-" <> &1))
        {:ins, lines} -> Enum.map(lines, &("+" <> &1))
      end)

    %{
      content: Enum.join(diff_lines, "\n"),
      first_changed_line: first_changed + 1
    }
  end

  defp resolve_path(path) when not is_binary(path) do
    {:error, "参数错误：file_path 必须是字符串"}
  end

  defp resolve_path("~/" <> rest) do
    {:ok, Path.join(System.user_home!(), rest) |> Path.expand()}
  end

  defp resolve_path(path), do: {:ok, Path.expand(path)}

  defp check_readable(path) do
    cond do
      not File.exists?(path) ->
        {:error, "File not found: #{path}"}

      File.dir?(path) ->
        {:error, "#{path}: Is a directory"}

      true ->
        case File.stat(path) do
          {:ok, %{access: access}} when access in [:read_write] -> :ok
          {:ok, %{access: :read}} -> {:error, "#{path}: Read-only file (EACCES)"}
          {:ok, _} -> {:error, "#{path}: Permission denied (EACCES)"}
          {:error, reason} -> {:error, "#{path}: #{inspect(reason)}"}
        end
    end
  end

  defp validate_edit_params(params) do
    cond do
      params.old_string == "" ->
        {:error, "old_string cannot be empty"}

      params.old_string == params.new_string ->
        {:error, "No changes made: old_string and new_string are identical"}

      true ->
        :ok
    end
  end

  # ── 两层匹配策略 ──

  defp apply_edit(content, old_str, new_str, replace_all) do
    # 第一层：精确匹配
    case count_occurrences(content, old_str) do
      0 ->
        # 第二层：模糊匹配
        fuzzy_edit(content, old_str, new_str, replace_all)

      1 ->
        new_content = String.replace(content, old_str, new_str, global: false)
        {:ok, new_content, 1}

      n when replace_all ->
        new_content = String.replace(content, old_str, new_str)
        {:ok, new_content, n}

      n ->
        {:error,
         "Found #{n} occurrences of the text. The text must be unique. Please provide more context to make it unique."}
    end
  end

  defp fuzzy_edit(content, old_str, new_str, replace_all) do
    normalized_content = normalize(content)
    normalized_old = normalize(old_str)

    case count_occurrences(normalized_content, normalized_old) do
      0 ->
        {:error,
         "Could not find the exact text. The old text must match exactly including all whitespace and newlines."}

      1 ->
        # 找到模糊匹配位置，在原文中定位对应范围
        case find_fuzzy_range(content, old_str) do
          {:ok, start, len} ->
            before = binary_part(content, 0, start)
            after_text = binary_part(content, start + len, byte_size(content) - start - len)
            {:ok, before <> new_str <> after_text, 1}

          :error ->
            {:error, "Could not find the exact text after fuzzy matching."}
        end

      n when replace_all ->
        new_content = fuzzy_replace_all(content, old_str, new_str)
        {:ok, new_content, n}

      n ->
        {:error,
         "Found #{n} occurrences of the text. The text must be unique. Please provide more context to make it unique."}
    end
  end

  # ── 模糊匹配定位 ──

  defp find_fuzzy_range(content, old_str) do
    normalized_old = normalize(old_str)
    # 按行滑动窗口查找
    content_lines = String.split(content, "\n")
    old_lines = String.split(old_str, "\n")
    old_line_count = length(old_lines)

    result =
      content_lines
      |> Enum.with_index()
      |> Enum.find(fn {_line, idx} ->
        window = Enum.slice(content_lines, idx, old_line_count)
        window_text = Enum.join(window, "\n")
        normalize(window_text) == normalized_old
      end)

    case result do
      {_line, idx} ->
        # 计算原始字节偏移
        before_lines = Enum.take(content_lines, idx)
        before_bytes = byte_size(Enum.join(before_lines, "\n"))
        start = if idx == 0, do: 0, else: before_bytes + 1

        matched_lines = Enum.slice(content_lines, idx, old_line_count)
        matched_bytes = byte_size(Enum.join(matched_lines, "\n"))

        {:ok, start, matched_bytes}

      nil ->
        :error
    end
  end

  defp fuzzy_replace_all(content, old_str, new_str) do
    # 逐次查找并替换
    case find_fuzzy_range(content, old_str) do
      {:ok, start, len} ->
        before = binary_part(content, 0, start)
        after_text = binary_part(content, start + len, byte_size(content) - start - len)
        fuzzy_replace_all(before <> new_str <> after_text, old_str, new_str)

      :error ->
        content
    end
  end

  # ── 5 步规范化 ──

  defp normalize(text) do
    text
    |> strip_trailing_spaces()
    |> normalize_quotes()
    |> normalize_dashes()
    |> normalize_spaces()
    |> :unicode.characters_to_nfd_binary()
  end

  # 1. 去尾部空格
  defp strip_trailing_spaces(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.join("\n")
  end

  # 2. 弯引号 → ASCII
  defp normalize_quotes(text) do
    text
    |> String.replace(~r/[\x{2018}\x{2019}\x{201A}\x{201B}]/u, "'")
    |> String.replace(~r/[\x{201C}\x{201D}\x{201E}\x{201F}]/u, "\"")
  end

  # 3. Unicode 破折号 → 连字符
  defp normalize_dashes(text) do
    String.replace(text, ~r/[\x{2010}-\x{2015}\x{2212}]/u, "-")
  end

  # 4. Unicode 空格 → 普通空格
  defp normalize_spaces(text) do
    String.replace(text, ~r/[\x{00A0}\x{2002}-\x{200A}\x{3000}]/u, " ")
  end

  # ── 辅助 ──

  defp count_occurrences(haystack, needle) do
    case String.split(haystack, needle) do
      parts -> length(parts) - 1
    end
  end
end
