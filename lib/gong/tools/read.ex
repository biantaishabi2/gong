defmodule Gong.Tools.Read do
  @moduledoc """
  文件读取 Action。

  支持分页读取（offset + limit）、行号显示、UTF-8 长行截断。
  二进制文件检测、路径校验、权限错误友好提示。
  """

  use Jido.Action,
    name: "read_file",
    description: "读取文件内容，支持分页",
    schema: [
      file_path: [type: :string, required: true, doc: "文件绝对路径"],
      offset: [type: :non_neg_integer, default: 0, doc: "起始行号（1-based，0 表示从头开始）"],
      limit: [type: :non_neg_integer, default: 2000, doc: "最多读取行数"]
    ]

  @max_line_length 2000
  @max_bytes 50_000
  @binary_check_bytes 8192

  @impl true
  def run(params, _context) do
    with {:ok, path} <- resolve_path(params.file_path),
         :ok <- check_exists(path),
         :ok <- check_not_directory(path),
         :ok <- check_readable(path) do
      if binary_file?(path) do
        read_binary(path)
      else
        read_text(path, params[:offset] || 0, params[:limit] || 2000)
      end
    end
  end

  # ── 路径处理 ──

  defp resolve_path(path) when not is_binary(path) do
    {:error, "参数错误：file_path 必须是字符串，收到 #{inspect(path)}"}
  end

  defp resolve_path(path) do
    expanded =
      path
      |> expand_tilde()
      |> Path.expand()

    {:ok, expanded}
  end

  defp expand_tilde("~/" <> rest) do
    Path.join(System.user_home!(), rest)
  end

  defp expand_tilde("~" <> _ = path), do: path
  defp expand_tilde(path), do: path

  # ── 前置检查 ──

  defp check_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, "#{path}: No such file or directory (ENOENT)"}
    end
  end

  defp check_not_directory(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} -> {:error, "#{path}: Is a directory"}
      _ -> :ok
    end
  end

  defp check_readable(path) do
    case File.stat(path) do
      {:ok, %{access: access}} when access in [:read, :read_write] -> :ok
      {:ok, _} -> {:error, "#{path}: Permission denied (EACCES)"}
      {:error, reason} -> {:error, "#{path}: #{inspect(reason)}"}
    end
  end

  # ── 二进制文件检测 ──

  defp binary_file?(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, device} ->
        chunk = IO.binread(device, @binary_check_bytes)
        File.close(device)

        case chunk do
          :eof -> false
          {:error, _} -> false
          data when is_binary(data) -> has_null_byte?(data)
        end

      _ ->
        false
    end
  end

  defp has_null_byte?(<<>>), do: false
  defp has_null_byte?(<<0, _rest::binary>>), do: true
  defp has_null_byte?(<<_byte, rest::binary>>), do: has_null_byte?(rest)

  # ── 二进制文件读取（返回 base64） ──

  defp read_binary(path) do
    case detect_image_type(path) do
      {:image, mime} ->
        data = File.read!(path)
        base64 = Base.encode64(data)

        {:ok,
         Gong.ToolResult.new(
           "[Image: #{mime}, #{byte_size(data)} bytes]",
           %{image: %{mime_type: mime, data: base64}, truncated: false, truncated_details: nil}
         )}

      :not_image ->
        {:error, "#{path}: Binary file detected, cannot display as text"}
    end
  end

  defp detect_image_type(path) do
    case File.read(path) do
      {:ok, <<0x89, 0x50, 0x4E, 0x47, _rest::binary>>} -> {:image, "image/png"}
      {:ok, <<0xFF, 0xD8, 0xFF, _rest::binary>>} -> {:image, "image/jpeg"}
      {:ok, <<"GIF8", _rest::binary>>} -> {:image, "image/gif"}
      {:ok, <<"RIFF", _::32, "WEBP", _rest::binary>>} -> {:image, "image/webp"}
      _ -> :not_image
    end
  end

  # ── 文本文件读取 ──

  defp read_text(path, offset, limit) do
    lines = File.stream!(path) |> Enum.to_list()
    total_lines = length(lines)

    # offset 是 1-based，0 表示从头
    start_line = if offset <= 0, do: 1, else: offset

    cond do
      total_lines == 0 ->
        {:ok,
         Gong.ToolResult.new(
           "",
           %{truncated: false, truncated_details: nil}
         )}

      start_line > total_lines ->
        {:error,
         "Offset #{start_line} is beyond end of file (#{total_lines} lines total)"}

      true ->
        selected =
          lines
          |> Enum.drop(start_line - 1)
          |> Enum.take(limit)

        output_lines = length(selected)
        remaining = total_lines - (start_line - 1) - output_lines

        # 格式化：行号前缀 + 长行截断
        formatted =
          selected
          |> Enum.with_index(start_line)
          |> Enum.map(fn {line, num} ->
            clean = String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
            truncated_line = truncate_long_line(clean)
            format_line_number(num, truncated_line)
          end)
          |> Enum.join("\n")

        # 字节截断
        trunc_result = Gong.Truncate.truncate(formatted, :head, max_bytes: @max_bytes)
        final_content = trunc_result.content
        truncated_by_bytes = trunc_result.truncated

        truncated = remaining > 0 or truncated_by_bytes
        details = build_truncation_details(total_lines, start_line, output_lines, remaining, truncated_by_bytes, limit)

        # 续读提示
        hint =
          cond do
            truncated_by_bytes ->
              next_offset = start_line + trunc_result.output_lines
              "\n[Use offset=#{next_offset} to continue reading]"

            remaining > 0 ->
              next_offset = start_line + output_lines
              "\n[#{remaining} more lines. Use offset=#{next_offset} to continue.]"

            true ->
              ""
          end

        {:ok,
         Gong.ToolResult.new(
           final_content <> hint,
           %{truncated: truncated, truncated_details: details}
         )}
    end
  end

  # 行号格式："     {n}\t{line}"
  defp format_line_number(num, line) do
    padded = num |> Integer.to_string() |> String.pad_leading(6)
    "#{padded}\t#{line}"
  end

  # 长行截断
  defp truncate_long_line(line) when byte_size(line) <= @max_line_length, do: line

  defp truncate_long_line(line) do
    truncated = String.slice(line, 0, @max_line_length)
    remaining = String.length(line) - @max_line_length
    "#{truncated}... [#{remaining} chars truncated]"
  end

  defp build_truncation_details(total, start, output, remaining, by_bytes, limit) do
    cond do
      by_bytes ->
        %{
          truncated_by: :bytes,
          total_lines: total,
          output_lines: output,
          byte_limit: @max_bytes
        }

      remaining > 0 ->
        %{
          truncated_by: :lines,
          total_lines: total,
          output_lines: output,
          start_line: start,
          limit: limit
        }

      true ->
        nil
    end
  end
end
