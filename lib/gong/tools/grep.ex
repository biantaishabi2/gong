defmodule Gong.Tools.Grep do
  @moduledoc """
  内容搜索 Action。

  基于 ripgrep (rg) 搜索文件内容，支持正则、glob 过滤、上下文行数。
  截断策略：head + line。
  """

  use Jido.Action,
    name: "grep",
    description: "搜索文件内容",
    schema: [
      pattern: [type: :string, required: true, doc: "正则表达式模式"],
      path: [type: :string, default: ".", doc: "搜索路径"],
      glob: [type: :string, doc: "文件 glob 过滤"],
      context: [type: :non_neg_integer, default: 0, doc: "上下文行数"],
      ignore_case: [type: :boolean, default: false, doc: "忽略大小写"],
      fixed_strings: [type: :boolean, default: false, doc: "字面匹配（非正则）"],
      output_mode: [type: :string, default: "content", doc: "输出模式：content/files_with_matches/count"]
    ]

  @max_matches 100
  @max_line_length 500
  @max_bytes 50_000

  @impl true
  def run(params, _context) do
    path = params[:path] || "."
    expanded = expand_path(path)

    if not File.exists?(expanded) do
      {:error, "#{expanded}: No such file or directory (ENOENT)"}
    else
      run_grep(params, expanded)
    end
  end

  defp expand_path("~/" <> rest), do: Path.join(System.user_home!(), rest) |> Path.expand()
  defp expand_path(path), do: Path.expand(path)

  defp run_grep(params, path) do
    args = build_args(params, path)

    case System.cmd("rg", args, stderr_to_stdout: true) do
      {output, 0} ->
        parse_output(output, params[:output_mode] || "content")

      {_output, 1} ->
        # rg exit 1 = no matches
        {:ok, Gong.ToolResult.new("No matches found.", %{matches: [], total: 0, truncated: false})}

      {output, 2} ->
        {:error, "grep error: #{String.trim(output)}"}

      {_output, code} ->
        {:error, "rg exited with code #{code}"}
    end
  rescue
    _e in ErlangError ->
      # rg 不存在时 fallback 到 grep
      fallback_grep(params, path)
  end

  defp build_args(params, path) do
    mode = params[:output_mode] || "content"

    # --json 只在 content 模式下使用（与 --files-with-matches/--count 冲突）
    args =
      if mode == "content" do
        ["--json", "--line-number", "--color=never", "--hidden", "--max-count=#{@max_matches}"]
      else
        ["--color=never", "--hidden", "--max-count=#{@max_matches}"]
      end

    args = if params[:ignore_case], do: args ++ ["--ignore-case"], else: args
    args = if params[:fixed_strings], do: args ++ ["--fixed-strings"], else: args
    args = if params[:glob], do: args ++ ["--glob", params.glob], else: args

    args =
      if (params[:context] || 0) > 0 do
        args ++ ["--context=#{params.context}"]
      else
        args
      end

    args = if mode == "files_with_matches", do: args ++ ["--files-with-matches"], else: args
    args = if mode == "count", do: args ++ ["--count"], else: args

    args ++ [params.pattern, path]
  end

  defp parse_output(output, "files_with_matches") do
    files =
      output
      |> String.split("\n", trim: true)
      |> Enum.take(@max_matches)

    {:ok,
     Gong.ToolResult.new(
       Enum.join(files, "\n"),
       %{files: files, total: length(files), truncated: false}
     )}
  end

  defp parse_output(output, "count") do
    {:ok, Gong.ToolResult.new(String.trim(output), %{matches: [], total: 0, truncated: false})}
  end

  defp parse_output(output, "content") do
    lines = String.split(output, "\n", trim: true)

    matches =
      lines
      |> Enum.flat_map(&parse_json_line/1)
      |> Enum.take(@max_matches)

    total = length(matches)
    truncated = total >= @max_matches

    content =
      matches
      |> Enum.map(&format_match/1)
      |> Enum.join("\n")

    # 字节截断
    {final_content, byte_truncated} = maybe_truncate(content)
    truncated = truncated or byte_truncated

    hint = if truncated, do: "\n[Results truncated at #{@max_matches} matches or #{@max_bytes} bytes]", else: ""

    {:ok,
     Gong.ToolResult.new(
       final_content <> hint,
       %{matches: matches, total: total, truncated: truncated}
     )}
  end

  defp parse_json_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "match", "data" => data}} ->
        [
          %{
            file: data["path"]["text"],
            line_number: data["line_number"],
            line: truncate_line(data["lines"]["text"] || "")
          }
        ]

      _ ->
        []
    end
  end

  defp format_match(%{file: file, line_number: num, line: line}) do
    "#{file}:#{num}: #{String.trim_trailing(line, "\n")}"
  end

  defp truncate_line(line) when byte_size(line) <= @max_line_length, do: line

  defp truncate_line(line) do
    String.slice(line, 0, @max_line_length) <> "... [truncated]"
  end

  defp maybe_truncate(content) when byte_size(content) <= @max_bytes, do: {content, false}

  defp maybe_truncate(content) do
    %Gong.Truncate.Result{content: truncated} =
      Gong.Truncate.truncate(content, :head, max_bytes: @max_bytes)

    {truncated, true}
  end

  # ── Fallback: 系统 grep ──

  defp fallback_grep(params, path) do
    args = ["-rn"]
    args = if params[:ignore_case], do: args ++ ["-i"], else: args
    args = if params[:fixed_strings], do: args ++ ["-F"], else: args

    args =
      if (params[:context] || 0) > 0 do
        args ++ ["-C", "#{params.context}"]
      else
        args
      end

    args = args ++ [params.pattern, path]

    case System.cmd("grep", args, stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n", trim: true) |> Enum.take(@max_matches)
        {:ok, Gong.ToolResult.new(Enum.join(lines, "\n"), %{matches: [], total: length(lines), truncated: false})}

      {_output, 1} ->
        {:ok, Gong.ToolResult.new("No matches found.", %{matches: [], total: 0, truncated: false})}

      {output, _} ->
        {:error, "grep error: #{String.trim(output)}"}
    end
  end
end
