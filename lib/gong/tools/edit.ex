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
      old_string: [type: :string, required: false, doc: "要替换的文本"],
      new_string: [type: :string, required: false, doc: "替换后的文本"],
      replace_all: [type: :boolean, default: false, doc: "是否替换所有匹配"],
      mode: [type: :string, default: "replace", doc: "编辑模式: replace | diff"],
      diff: [type: :string, required: false, doc: "unified diff 内容（mode=diff 时使用）"]
    ]

  # 超大文件阈值：10MB
  @max_edit_file_bytes 10_485_760

  @impl true
  def run(%{mode: "diff"} = params, context) do
    run_diff_mode(params, context)
  end

  def run(params, context) do
    workspace = Map.get(context, :workspace)

    with {:ok, path} <- resolve_path(params.file_path),
         :ok <- check_path_safe(path, workspace),
         :ok <- check_readable(path),
         :ok <- check_file_size(path),
         :ok <- check_not_binary(path),
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
             Gong.ToolResult.new(
               "Edited: #{path} (#{count} replacements)",
               %{file_path: path, replacements: count, diff: diff}
             )}

          {:error, reason} ->
            {:error, "#{path}: Write failed (#{reason})"}
        end
      end
    end
  end

  # ── Diff 模式 ──

  defp run_diff_mode(params, context) do
    workspace = Map.get(context, :workspace)

    with {:ok, path} <- resolve_path(params.file_path),
         :ok <- check_path_safe(path, workspace),
         :ok <- check_readable(path),
         {:ok, raw} <- File.read(path) do
      case apply_unified_diff(raw, params.diff) do
        {:ok, new_content, changes} ->
          case File.write(path, new_content) do
            :ok ->
              {:ok, Gong.ToolResult.new(
                "Edited: #{path} (#{changes} replacements, diff mode)",
                %{file_path: path, replacements: changes, mode: "diff"}
              )}

            {:error, reason} ->
              {:error, "#{path}: Write failed (#{reason})"}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp apply_unified_diff(content, diff_text) do
    lines = String.split(content, "\n")
    diff_lines = String.split(diff_text, "\n")

    # 解析 diff hunks
    {result_lines, changes} = apply_diff_hunks(lines, diff_lines, 0, 0)

    if changes > 0 do
      {:ok, Enum.join(result_lines, "\n"), changes}
    else
      {:error, "No changes applied from diff"}
    end
  end

  defp apply_diff_hunks(original_lines, diff_lines, _offset, changes) do
    # 解析 unified diff 行
    {additions, deletions} = parse_diff_operations(diff_lines)

    # 按行号逆序应用（避免偏移变化）
    result = apply_operations(original_lines, deletions, additions)
    total_changes = length(additions) + length(deletions)

    {result, changes + total_changes}
  end

  defp parse_diff_operations(diff_lines) do
    # 跟踪当前行号
    {adds, dels, _line} =
      Enum.reduce(diff_lines, {[], [], 0}, fn line, {adds, dels, line_num} ->
        cond do
          String.starts_with?(line, "@@") ->
            # 解析 hunk header: @@ -start,count +start,count @@
            case Regex.run(~r/@@ -(\d+)/, line) do
              [_, start] -> {adds, dels, String.to_integer(start) - 1}
              _ -> {adds, dels, line_num}
            end

          String.starts_with?(line, "-") ->
            {adds, dels ++ [{line_num, String.slice(line, 1..-1//1)}], line_num + 1}

          String.starts_with?(line, "+") ->
            {adds ++ [{line_num, String.slice(line, 1..-1//1)}], dels, line_num}

          String.starts_with?(line, " ") ->
            {adds, dels, line_num + 1}

          true ->
            {adds, dels, line_num + 1}
        end
      end)

    {adds, dels}
  end

  defp apply_operations(lines, deletions, additions) do
    # 简化实现：根据 diff 重建内容
    # 先删除标记行，再插入新行
    indexed = Enum.with_index(lines)

    del_indices = MapSet.new(Enum.map(deletions, fn {idx, _} -> idx end))

    # 过滤掉被删除的行
    kept =
      indexed
      |> Enum.reject(fn {_line, idx} -> MapSet.member?(del_indices, idx) end)
      |> Enum.map(fn {line, _idx} -> line end)

    # 插入新行（在删除位置之后）
    if Enum.empty?(additions) do
      kept
    else
      # 找到第一个删除位置作为插入点
      insert_at = case deletions do
        [{idx, _} | _] -> idx
        [] -> length(kept)
      end

      add_lines = Enum.map(additions, fn {_, content} -> content end)
      List.insert_at(kept, insert_at, add_lines) |> List.flatten()
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

  # ── 安全检查 ──

  defp check_path_safe(_path, nil), do: :ok

  defp check_path_safe(path, workspace) do
    expanded = Path.expand(path)
    ws_expanded = Path.expand(workspace)

    if String.starts_with?(expanded, ws_expanded <> "/") or expanded == ws_expanded do
      :ok
    else
      {:error, "Path traversal blocked: #{path} is outside workspace"}
    end
  end

  defp check_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_edit_file_bytes ->
        mb = Float.round(size / 1_048_576, 1)
        {:error, "File too large (#{mb} MB). Maximum is #{div(@max_edit_file_bytes, 1_048_576)} MB."}

      _ ->
        :ok
    end
  end

  defp check_not_binary(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} ->
        chunk = IO.binread(device, 8192)
        File.close(device)

        case chunk do
          :eof ->
            :ok

          data when is_binary(data) ->
            if :binary.match(data, <<0>>) != :nomatch do
              {:error, "Binary file detected: #{path}. Edit only supports text files."}
            else
              :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
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
