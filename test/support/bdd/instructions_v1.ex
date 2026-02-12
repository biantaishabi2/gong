defmodule Gong.BDD.Instructions.V1 do
  @moduledoc "Gong BDD v1 指令运行时实现"

  import ExUnit.Assertions

  @type ctx :: map()
  @type meta :: map()

  # 编译期提取已实现的指令列表
  @supported_instructions (
    __ENV__.file
    |> File.read!()
    |> then(fn src ->
      Regex.scan(~r/\{\:(?:given|when|then),\s+\:([a-zA-Z0-9_]+)\}\s*->/, src,
        capture: :all_but_first
      )
    end)
    |> List.flatten()
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
    |> Enum.sort()
  )

  @spec capabilities() :: MapSet.t(atom())
  def capabilities, do: MapSet.new(@supported_instructions)

  @spec new_run_id() :: String.t()
  def new_run_id do
    "bdd_run_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @spec run_step!(ctx(), :given | :when | :then, atom(), map(), meta(), term()) :: ctx()
  def run_step!(ctx, kind, name, args, meta, _step_id \\ nil) do
    scenario_id = Map.get(ctx, :scenario_id)

    try do
      run!(ctx, kind, name, args, meta)
    rescue
      e in [ExUnit.AssertionError, ArgumentError] ->
        dump_evidence(ctx, scenario_id, meta, e)
        reraise(e, __STACKTRACE__)

      e ->
        dump_evidence(ctx, scenario_id, meta, e)
        reraise(e, __STACKTRACE__)
    end
  end

  @spec run!(ctx(), :given | :when | :then, atom(), map(), meta()) :: ctx()
  def run!(ctx, kind, name, args, meta \\ %{})

  # ── Common: 测试基础设施 ──

  def run!(ctx, kind, name, args, meta) do
    case {kind, name} do
      {:given, :create_temp_dir} ->
        create_temp_dir!(ctx, args, meta)

      {:given, :create_temp_file} ->
        create_temp_file!(ctx, args, meta)

      {:given, :create_large_file} ->
        create_large_file!(ctx, args, meta)

      {:given, :create_binary_file} ->
        create_binary_file!(ctx, args, meta)

      {:given, :create_png_file} ->
        create_png_file!(ctx, args, meta)

      {:given, :create_symlink} ->
        create_symlink!(ctx, args, meta)

      {:given, :set_file_permission} ->
        set_file_permission!(ctx, args, meta)

      # ── Tools: 工具调用 ──

      {:when, :tool_read} ->
        tool_read!(ctx, args, meta)

      # ── Assertions: 结果断言 ──

      {:then, :assert_tool_success} ->
        assert_tool_success!(ctx, args, meta)

      {:then, :assert_tool_error} ->
        assert_tool_error!(ctx, args, meta)

      {:then, :assert_tool_truncated} ->
        assert_tool_truncated!(ctx, args, meta)

      {:then, :assert_read_image} ->
        assert_read_image!(ctx, args, meta)

      {:then, :assert_read_text} ->
        assert_read_text!(ctx, args, meta)

      _ ->
        raise ArgumentError, "未实现的指令: {#{kind}, #{name}}"
    end
  end

  # ── Common 实现 ──

  defp create_temp_dir!(ctx, _args, _meta) do
    dir = Path.join(System.tmp_dir!(), "gong_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    Map.put(ctx, :workspace, dir)
  end

  defp create_temp_file!(ctx, %{path: path, content: content}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 处理 DSL 中的转义换行
    decoded_content = unescape(content)
    File.write!(full, decoded_content)
    ctx
  end

  defp create_large_file!(ctx, %{lines: lines} = args, _meta) do
    path = Map.get(args, :path, "large_file.txt")
    line_length = Map.get(args, :line_length, 20)
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))

    content =
      1..lines
      |> Enum.map(fn n ->
        padding = String.duplicate("x", max(0, line_length - String.length("line #{n}")))
        "line #{n}#{padding}"
      end)
      |> Enum.join("\n")

    File.write!(full, content <> "\n")
    ctx
  end

  defp create_binary_file!(ctx, %{path: path, bytes: bytes}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 写入含 null 字节的二进制数据
    data = :crypto.strong_rand_bytes(div(bytes, 2)) |> then(fn d -> <<0>> <> d end)
    padded = if byte_size(data) < bytes, do: data <> :binary.copy(<<0>>, bytes - byte_size(data)), else: binary_part(data, 0, bytes)
    File.write!(full, padded)
    ctx
  end

  defp create_png_file!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    # 最小 PNG: 8 字节 signature + 空 IHDR
    png_header = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>
    File.write!(full, png_header <> :binary.copy(<<0>>, 100))
    ctx
  end

  defp create_symlink!(ctx, %{link: link, target: target}, _meta) do
    link_full = Path.join(ctx.workspace, link)
    target_full = Path.join(ctx.workspace, target)
    File.mkdir_p!(Path.dirname(link_full))
    File.ln_s!(target_full, link_full)
    ctx
  end

  defp set_file_permission!(ctx, %{path: path, mode: mode}, _meta) do
    full = Path.join(ctx.workspace, path)
    mode_int = String.to_integer(mode, 8)
    File.chmod!(full, mode_int)
    ctx
  end

  # ── Tools 实现 ──

  defp tool_read!(ctx, args, _meta) do
    path = Map.get(args, :path, "")

    # 如果 path 不是绝对路径也不是 ~/ 开头，拼接 workspace
    file_path =
      cond do
        String.starts_with?(path, "/") -> path
        String.starts_with?(path, "~/") -> path
        true -> Path.join(ctx.workspace, path)
      end

    params = %{file_path: file_path}
    params = if args[:offset], do: Map.put(params, :offset, args.offset), else: params
    params = if args[:limit], do: Map.put(params, :limit, args.limit), else: params

    result = Gong.Tools.Read.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Assertion 实现 ──

  defp assert_tool_success!(ctx, args, _meta) do
    result = ctx.last_result
    assert {:ok, data} = result, "期望成功，实际：#{inspect(result)}"

    if cc = args[:content_contains] do
      assert data.content =~ unescape(cc),
        "期望内容包含 #{inspect(cc)}，实际：#{String.slice(data.content, 0, 200)}"
    end

    if args[:truncated] != nil do
      assert data.truncated == args.truncated,
        "期望 truncated=#{args.truncated}，实际：#{data.truncated}"
    end

    ctx
  end

  defp assert_tool_error!(ctx, %{error_contains: expected}, _meta) do
    result = ctx.last_result
    assert {:error, error} = result, "期望错误，实际：#{inspect(result)}"
    error_msg = if is_binary(error), do: error, else: inspect(error)

    assert error_msg =~ unescape(expected),
      "期望错误包含 #{inspect(expected)}，实际：#{error_msg}"

    ctx
  end

  defp assert_tool_truncated!(ctx, args, _meta) do
    result = ctx.last_result
    assert {:ok, data} = result
    assert data.truncated == true, "期望 truncated=true"

    if tb = args[:truncated_by] do
      assert data.truncated_details != nil
      assert to_string(data.truncated_details.truncated_by) == tb,
        "期望 truncated_by=#{tb}，实际：#{inspect(data.truncated_details.truncated_by)}"
    end

    if ol = args[:original_lines] do
      assert data.truncated_details.total_lines == ol,
        "期望 total_lines=#{ol}，实际：#{data.truncated_details.total_lines}"
    end

    ctx
  end

  defp assert_read_image!(ctx, %{mime_type: expected_mime}, _meta) do
    result = ctx.last_result
    assert {:ok, data} = result
    assert data[:image] != nil, "期望返回图片数据"
    assert data.image.mime_type == expected_mime,
      "期望 MIME=#{expected_mime}，实际：#{data.image.mime_type}"
    ctx
  end

  defp assert_read_text!(ctx, _args, _meta) do
    result = ctx.last_result
    assert {:ok, data} = result
    assert data[:image] == nil, "期望返回文本，但收到图片数据"
    ctx
  end

  # ── Helpers ──

  defp unescape(str) when is_binary(str) do
    str
    |> String.replace("\\n", "\n")
    |> String.replace("\\t", "\t")
    |> String.replace("\\r", "\r")
  end

  defp unescape(other), do: other

  # ── 错误诊断 ──

  defp dump_evidence(_ctx, scenario_id, meta, error) do
    IO.puts("\n=== BDD 失败诊断 ===")
    IO.puts("场景: #{scenario_id}")

    if meta[:file] do
      IO.puts("文件: #{meta.file}:#{meta[:line]}")
    end

    if meta[:raw] do
      IO.puts("步骤: #{meta.raw}")
    end

    IO.puts("错误: #{Exception.message(error)}")
    IO.puts("=== 诊断结束 ===\n")
  end
end
