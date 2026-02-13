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

      {:given, :set_var} ->
        set_var!(ctx, args, meta)

      {:given, :generate_content} ->
        generate_content!(ctx, args, meta)

      # ── Tools: 工具调用 ──

      {:when, :tool_read} ->
        tool_read!(ctx, args, meta)

      {:when, :tool_write} ->
        tool_write!(ctx, args, meta)

      {:when, :tool_edit} ->
        tool_edit!(ctx, args, meta)

      {:when, :tool_bash} ->
        tool_bash!(ctx, args, meta)

      {:when, :tool_grep} ->
        tool_grep!(ctx, args, meta)

      {:when, :tool_find} ->
        tool_find!(ctx, args, meta)

      {:when, :tool_ls} ->
        tool_ls!(ctx, args, meta)

      # ── 截断操作 ──

      {:when, :truncate_head} ->
        truncate_head!(ctx, args, meta)

      {:when, :truncate_tail} ->
        truncate_tail!(ctx, args, meta)

      {:when, :truncate_line} ->
        truncate_line!(ctx, args, meta)

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

      {:then, :assert_file_exists} ->
        assert_file_exists!(ctx, args, meta)

      {:then, :assert_file_content} ->
        assert_file_content!(ctx, args, meta)

      {:then, :assert_result_field} ->
        assert_result_field!(ctx, args, meta)

      {:then, :assert_exit_code} ->
        assert_exit_code!(ctx, args, meta)

      {:then, :assert_output_contains} ->
        assert_output_contains!(ctx, args, meta)

      {:then, :assert_output_not_contains} ->
        assert_output_not_contains!(ctx, args, meta)

      {:then, :assert_truncation_result} ->
        assert_truncation_result!(ctx, args, meta)

      {:then, :assert_truncation_notification} ->
        assert_truncation_notification!(ctx, args, meta)

      # ── Agent 集成 ──

      {:given, :configure_agent} ->
        configure_agent!(ctx, args, meta)

      {:given, :mock_llm_response} ->
        mock_llm_response!(ctx, args, meta)

      {:given, :register_hook} ->
        register_hook!(ctx, args, meta)

      {:given, :attach_telemetry_handler} ->
        attach_telemetry_handler!(ctx, args, meta)

      {:given, :configure_hooks} ->
        configure_hooks!(ctx, args, meta)

      {:when, :agent_chat} ->
        agent_chat!(ctx, args, meta)

      {:when, :agent_stream} ->
        agent_stream!(ctx, args, meta)

      {:when, :agent_abort} ->
        agent_abort!(ctx, args, meta)

      {:when, :trigger_compaction} ->
        trigger_compaction!(ctx, args, meta)

      {:then, :assert_agent_reply} ->
        assert_agent_reply!(ctx, args, meta)

      {:then, :assert_tool_was_called} ->
        assert_tool_was_called!(ctx, args, meta)

      {:then, :assert_tool_not_called} ->
        assert_tool_not_called!(ctx, args, meta)

      {:then, :assert_hook_fired} ->
        assert_hook_fired!(ctx, args, meta)

      {:then, :assert_hook_blocked} ->
        assert_hook_blocked!(ctx, args, meta)

      {:then, :assert_telemetry_received} ->
        assert_telemetry_received!(ctx, args, meta)

      {:then, :assert_hook_error_logged} ->
        assert_hook_error_logged!(ctx, args, meta)

      {:then, :assert_result_content_contains} ->
        assert_result_content_contains!(ctx, args, meta)

      {:then, :assert_result_content_not_contains} ->
        assert_result_content_not_contains!(ctx, args, meta)

      {:then, :assert_conversation_contains} ->
        assert_conversation_contains!(ctx, args, meta)

      {:then, :assert_stream_events} ->
        assert_stream_events!(ctx, args, meta)

      {:then, :assert_no_crash} ->
        assert_no_crash!(ctx, args, meta)

      {:then, :assert_last_error} ->
        assert_last_error!(ctx, args, meta)

      # ── Tape 存储 ──

      {:given, :tape_init} ->
        tape_init_given!(ctx, args, meta)

      {:given, :tape_append} ->
        tape_append_given!(ctx, args, meta)

      {:given, :tape_handoff} ->
        tape_handoff_given!(ctx, args, meta)

      {:given, :tape_fork} ->
        tape_fork_given!(ctx, args, meta)

      {:given, :tape_close_db} ->
        tape_close_db!(ctx, args, meta)

      {:given, :tape_restore_parent} ->
        tape_restore_parent!(ctx, args, meta)

      {:given, :corrupt_jsonl} ->
        corrupt_jsonl!(ctx, args, meta)

      {:given, :delete_file} ->
        delete_file!(ctx, args, meta)

      {:given, :clear_file} ->
        clear_file!(ctx, args, meta)

      {:when, :when_tape_init} ->
        tape_init_when!(ctx, args, meta)

      {:when, :when_tape_append} ->
        tape_append_when!(ctx, args, meta)

      {:when, :when_tape_handoff} ->
        tape_handoff_when!(ctx, args, meta)

      {:when, :when_tape_between_anchors} ->
        tape_between_anchors_when!(ctx, args, meta)

      {:when, :when_tape_search} ->
        tape_search_when!(ctx, args, meta)

      {:when, :when_tape_fork} ->
        tape_fork_when!(ctx, args, meta)

      {:when, :when_tape_merge} ->
        tape_merge_when!(ctx, args, meta)

      {:when, :when_tape_rebuild_index} ->
        tape_rebuild_index_when!(ctx, args, meta)

      {:then, :assert_dir_exists} ->
        assert_dir_exists!(ctx, args, meta)

      {:then, :assert_db_exists} ->
        assert_db_exists!(ctx, args, meta)

      {:then, :assert_entry_count} ->
        assert_entry_count!(ctx, args, meta)

      {:then, :assert_anchor_count} ->
        assert_anchor_count!(ctx, args, meta)

      {:then, :assert_jsonl_contains} ->
        assert_jsonl_contains!(ctx, args, meta)

      {:then, :assert_jsonl_not_contains} ->
        assert_jsonl_not_contains!(ctx, args, meta)

      {:then, :assert_query_results} ->
        assert_query_results!(ctx, args, meta)

      {:then, :assert_search_results} ->
        assert_search_results!(ctx, args, meta)

      {:then, :assert_tape_error} ->
        assert_tape_error!(ctx, args, meta)

      {:then, :assert_fork_cleaned} ->
        assert_fork_cleaned!(ctx, args, meta)

      # ── Compaction 压缩 ──

      {:given, :compaction_messages} ->
        compaction_messages!(ctx, args, meta)

      {:given, :compaction_messages_with_system} ->
        compaction_messages_with_system!(ctx, args, meta)

      {:given, :compaction_lock_acquired} ->
        compaction_lock_acquired!(ctx, args, meta)

      {:given, :compaction_summarize_fn_ok} ->
        compaction_summarize_fn_ok!(ctx, args, meta)

      {:given, :compaction_summarize_fn_fail} ->
        compaction_summarize_fn_fail!(ctx, args, meta)

      {:when, :when_estimate_tokens} ->
        when_estimate_tokens!(ctx, args, meta)

      {:when, :when_compact} ->
        when_compact!(ctx, args, meta)

      {:when, :when_compact_and_handoff} ->
        when_compact_and_handoff!(ctx, args, meta)

      {:when, :when_acquire_lock} ->
        when_acquire_lock!(ctx, args, meta)

      {:then, :assert_token_estimate} ->
        assert_token_estimate!(ctx, args, meta)

      {:then, :assert_compacted} ->
        assert_compacted!(ctx, args, meta)

      {:then, :assert_not_compacted} ->
        assert_not_compacted!(ctx, args, meta)

      {:then, :assert_summary_exists} ->
        assert_summary_exists!(ctx, args, meta)

      {:then, :assert_summary_nil} ->
        assert_summary_nil!(ctx, args, meta)

      {:then, :assert_system_preserved} ->
        assert_system_preserved!(ctx, args, meta)

      {:then, :assert_compaction_error} ->
        assert_compaction_error!(ctx, args, meta)

      {:then, :assert_tape_has_compaction_anchor} ->
        assert_tape_has_compaction_anchor!(ctx, args, meta)

      _ ->
        raise ArgumentError, "未实现的指令: {#{kind}, #{name}}"
    end
  end

  # ── Common 实现 ──

  defp create_temp_dir!(ctx, _args, _meta) do
    dir = Path.join(System.tmp_dir!(), "gong_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn ->
      # 恢复权限后再删除（chmod 测试可能锁住子目录）
      System.cmd("chmod", ["-R", "755", dir], stderr_to_stdout: true)
      File.rm_rf!(dir)
    end)
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

  # ── Tools 实现：write ──

  defp tool_write!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    content = unescape(Map.get(args, :content, ""))

    result = Gong.Tools.Write.run(%{file_path: path, content: content}, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：edit ──

  defp tool_edit!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))

    params = %{
      file_path: path,
      old_string: unescape(args.old_string),
      new_string: unescape(args.new_string)
    }
    params = if args[:replace_all], do: Map.put(params, :replace_all, args.replace_all), else: params

    result = Gong.Tools.Edit.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：bash ──

  defp tool_bash!(ctx, args, _meta) do
    params = %{command: args.command}
    params = if args[:timeout], do: Map.put(params, :timeout, args.timeout), else: params
    params = if args[:cwd] do
      cwd = resolve_tool_path(ctx, args.cwd)
      Map.put(params, :cwd, cwd)
    else
      params
    end

    result = Gong.Tools.Bash.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：grep ──

  defp tool_grep!(ctx, args, _meta) do
    params = %{pattern: args.pattern}
    params = if args[:path], do: Map.put(params, :path, resolve_tool_path(ctx, args.path)), else: Map.put(params, :path, ctx.workspace)
    params = if args[:glob], do: Map.put(params, :glob, args.glob), else: params
    params = if args[:context], do: Map.put(params, :context, args.context), else: params
    params = if args[:ignore_case], do: Map.put(params, :ignore_case, args.ignore_case), else: params
    params = if args[:fixed_strings], do: Map.put(params, :fixed_strings, args.fixed_strings), else: params
    params = if args[:output_mode], do: Map.put(params, :output_mode, args.output_mode), else: params

    result = Gong.Tools.Grep.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：find ──

  defp tool_find!(ctx, args, _meta) do
    params = %{pattern: args.pattern}
    params = if args[:path], do: Map.put(params, :path, resolve_tool_path(ctx, args.path)), else: Map.put(params, :path, ctx.workspace)
    params = if args[:exclude], do: Map.put(params, :exclude, args.exclude), else: params
    params = if args[:limit], do: Map.put(params, :limit, args.limit), else: params

    result = Gong.Tools.Find.run(params, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── Tools 实现：ls ──

  defp tool_ls!(ctx, args, _meta) do
    path = resolve_tool_path(ctx, Map.get(args, :path, ""))
    result = Gong.Tools.Ls.run(%{path: path}, %{})
    Map.put(ctx, :last_result, result)
  end

  # ── 路径解析辅助 ──

  defp resolve_tool_path(ctx, path) do
    cond do
      String.starts_with?(path, "/") -> path
      String.starts_with?(path, "~/") -> path
      true -> Path.join(ctx.workspace, path)
    end
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

  # ── 文件断言 ──

  defp assert_file_exists!(ctx, %{path: path}, _meta) do
    full = Path.join(ctx.workspace, path)
    assert File.exists?(full), "期望文件存在: #{full}"
    ctx
  end

  defp assert_file_content!(ctx, %{path: path, expected: expected}, _meta) do
    full = Path.join(ctx.workspace, path)
    actual = File.read!(full)
    expected_decoded = unescape(expected)
    assert actual == expected_decoded,
      "期望文件内容为 #{inspect(expected_decoded)}，实际：#{inspect(actual)}"
    ctx
  end

  # ── 结果字段断言 ──

  defp assert_result_field!(ctx, %{field: field, expected: expected}, _meta) do
    assert {:ok, data} = ctx.last_result
    field_atom = String.to_existing_atom(field)
    actual = Map.get(data, field_atom)
    assert to_string(actual) == expected,
      "期望 #{field}=#{expected}，实际：#{inspect(actual)}"
    ctx
  end

  # ── Bash 特有断言 ──

  defp assert_exit_code!(ctx, %{expected: expected}, _meta) do
    assert {:ok, data} = ctx.last_result
    assert data.exit_code == expected,
      "期望 exit_code=#{expected}，实际：#{data.exit_code}"
    ctx
  end

  defp assert_output_contains!(ctx, %{text: text}, _meta) do
    assert {:ok, data} = ctx.last_result
    decoded = unescape(text)
    assert data.content =~ decoded,
      "期望输出包含 #{inspect(decoded)}，实际：#{String.slice(data.content, 0, 200)}"
    ctx
  end

  defp assert_output_not_contains!(ctx, %{text: text}, _meta) do
    assert {:ok, data} = ctx.last_result
    decoded = unescape(text)
    refute data.content =~ decoded,
      "期望输出不包含 #{inspect(decoded)}，但包含了"
    ctx
  end

  # ── Common 实现：变量 ──

  defp set_var!(ctx, %{name: name, value: value}, _meta) do
    decoded = unescape(value)
    Map.put(ctx, String.to_atom(name), decoded)
  end

  defp generate_content!(ctx, args, _meta) do
    name = args.name
    lines = args.lines
    line_length = Map.get(args, :line_length, 20)

    content =
      1..lines
      |> Enum.map(fn n ->
        prefix = "line #{n}"
        padding = String.duplicate("x", max(0, line_length - String.length(prefix)))
        prefix <> padding
      end)
      |> Enum.join("\n")

    Map.put(ctx, String.to_atom(name), content)
  end

  # ── 截断操作实现 ──

  defp truncate_head!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    opts = build_truncate_opts(args)
    result = Gong.Truncate.truncate(content, :head, opts)
    Map.put(ctx, :last_result, result)
  end

  defp truncate_tail!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    opts = build_truncate_opts(args)
    result = Gong.Truncate.truncate(content, :tail, opts)
    Map.put(ctx, :last_result, result)
  end

  defp truncate_line!(ctx, args, _meta) do
    content = Map.fetch!(ctx, String.to_atom(args.content_var))
    result = Gong.Truncate.truncate_line(content, args.max_chars)
    Map.put(ctx, :last_result, result)
  end

  defp build_truncate_opts(args) do
    opts = []
    opts = if args[:max_lines], do: [{:max_lines, args.max_lines} | opts], else: opts
    opts = if args[:max_bytes], do: [{:max_bytes, args.max_bytes} | opts], else: opts
    opts
  end

  # ── 截断断言实现 ──

  defp assert_truncation_result!(ctx, args, _meta) do
    result = ctx.last_result
    assert %Gong.Truncate.Result{} = result, "期望 Truncate.Result，实际：#{inspect(result)}"

    if args[:truncated] != nil do
      assert result.truncated == args.truncated,
        "期望 truncated=#{args.truncated}，实际：#{result.truncated}"
    end

    if tb = args[:truncated_by] do
      expected_by = String.to_existing_atom(tb)

      assert result.truncated_by == expected_by,
        "期望 truncated_by=#{tb}，实际：#{inspect(result.truncated_by)}"
    end

    if args[:output_lines] do
      assert result.output_lines == args.output_lines,
        "期望 output_lines=#{args.output_lines}，实际：#{result.output_lines}"
    end

    if args[:first_line_exceeds_limit] != nil do
      assert result.first_line_exceeds_limit == args.first_line_exceeds_limit,
        "期望 first_line_exceeds_limit=#{args.first_line_exceeds_limit}，实际：#{result.first_line_exceeds_limit}"
    end

    if args[:last_line_partial] != nil do
      assert result.last_line_partial == args.last_line_partial,
        "期望 last_line_partial=#{args.last_line_partial}，实际：#{result.last_line_partial}"
    end

    if cc = args[:content_contains] do
      decoded = unescape(cc)

      assert result.content =~ decoded,
        "期望 content 包含 #{inspect(decoded)}，实际：#{String.slice(result.content, 0, 200)}"
    end

    if args[:valid_utf8] == true do
      assert String.valid?(result.content),
        "期望 content 是合法 UTF-8，但包含无效字节"
    end

    ctx
  end

  defp assert_truncation_notification!(ctx, %{contains: text}, _meta) do
    # 用于工具集成测试，last_result 是 {:ok, %{content: ...}}
    assert {:ok, data} = ctx.last_result
    decoded = unescape(text)

    assert data.content =~ decoded,
      "期望截断通知包含 #{inspect(decoded)}，实际：#{String.slice(data.content, 0, 300)}"

    ctx
  end

  # ── Agent 配置实现 ──

  defp configure_agent!(ctx, _args, _meta) do
    # mock 测试用策略层（无 AgentServer），E2E 测试用 AgentServer
    # 根据 mock_queue 是否为空来区分
    agent = Gong.MockLLM.init_agent()

    ctx
    |> Map.put(:agent, agent)
    |> Map.put(:agent_mode, :mock)
    |> Map.put(:mock_queue, [])
    |> Map.put(:tool_call_log, [])
    |> Map.put(:hook_events, [])
    |> Map.put(:hooks, [])
    |> Map.put(:telemetry_events, [])
    |> Map.put(:telemetry_handlers, [])
    |> Map.put(:stream_events, [])
  end

  defp mock_llm_response!(ctx, args, _meta) do
    response =
      case args.response_type do
        "text" ->
          {:text, Map.get(args, :content, "")}

        "tool_call" ->
          tool = Map.get(args, :tool, "bash")
          tool_args = parse_tool_args(Map.get(args, :tool_args, ""), ctx)
          {:tool_calls, [%{name: tool, arguments: tool_args}]}

        "error" ->
          {:error, Map.get(args, :content, "LLM error")}

        "stream" ->
          {:text, Map.get(args, :content, "")}
      end

    queue = Map.get(ctx, :mock_queue, [])
    Map.put(ctx, :mock_queue, queue ++ [response])
  end

  # 解析管道分隔的工具参数：key1=value1|key2=value2
  # 支持 {{workspace}} 占位符替换
  defp parse_tool_args("", _ctx), do: %{}

  defp parse_tool_args(str, ctx) do
    str
    |> String.split("|")
    |> Enum.map(fn pair ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          resolved = String.replace(value, "{{workspace}}", Map.get(ctx, :workspace, ""))
          {key, resolved}
        [key] -> {key, ""}
      end
    end)
    |> Map.new()
  end

  defp register_hook!(ctx, %{module: module_name}, _meta) do
    # 解析模块名（支持 "Gong.TestHooks.AllowAll" 等格式）
    hook_module = resolve_hook_module(module_name)
    hooks = Map.get(ctx, :hooks, [])
    Map.put(ctx, :hooks, hooks ++ [hook_module])
  end

  defp attach_telemetry_handler!(ctx, %{event: event_str}, _meta) do
    # 解析事件名："gong.tool.start" → [:gong, :tool, :start]
    event = event_str |> String.split(".") |> Enum.map(&String.to_atom/1)
    handler_id = "bdd_telemetry_#{:erlang.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler_id,
      event,
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    # 测试结束后清理 handler
    ExUnit.Callbacks.on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    handlers = Map.get(ctx, :telemetry_handlers, [])
    Map.put(ctx, :telemetry_handlers, handlers ++ [handler_id])
  end

  defp configure_hooks!(ctx, %{hooks: hooks_str}, _meta) do
    # 逗号分隔的模块名列表
    hook_modules =
      hooks_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&resolve_hook_module/1)

    Map.put(ctx, :hooks, hook_modules)
  end

  defp resolve_hook_module(module_name) do
    # 支持短名和全名
    full_name =
      if String.starts_with?(module_name, "Elixir.") or String.starts_with?(module_name, "Gong.") do
        module_name
      else
        "Gong.TestHooks.#{module_name}"
      end

    Module.concat([full_name])
  end

  # ── Agent 操作实现 ──

  defp agent_chat!(ctx, %{prompt: prompt}, _meta) do
    queue = Map.get(ctx, :mock_queue, [])
    hooks = Map.get(ctx, :hooks, [])

    if queue != [] do
      # Mock 模式：策略层驱动（传入 hooks）
      agent = ctx.agent
      case Gong.MockLLM.run_chat(agent, prompt, queue, hooks) do
        {:ok, reply, updated_agent} ->
          ctx = collect_telemetry_events(ctx)

          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, reply)
          |> Map.put(:last_error, nil)
          |> Map.put(:mock_queue, [])

        {:error, reason, updated_agent} ->
          ctx = collect_telemetry_events(ctx)

          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, to_string(reason))
          |> Map.put(:last_error, reason)
          |> Map.put(:mock_queue, [])
      end
    else
      # E2E 模式：真实 AgentServer + LLM
      {:ok, pid} = Jido.AgentServer.start_link(agent: Gong.Agent)
      ExUnit.Callbacks.on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)

      # 在 prompt 前注入 workspace 路径，让 LLM 知道文件位置
      workspace = Map.get(ctx, :workspace, File.cwd!())
      full_prompt = "工作目录：#{workspace}\n所有文件操作使用绝对路径。\n\n#{prompt}"

      case Gong.Agent.ask_sync(pid, full_prompt, timeout: 60_000) do
        {:ok, reply} ->
          ctx
          |> Map.put(:agent_pid, pid)
          |> Map.put(:agent_mode, :e2e)
          |> Map.put(:last_reply, reply)
          |> Map.put(:last_error, nil)

        {:error, reason} ->
          ctx
          |> Map.put(:agent_pid, pid)
          |> Map.put(:agent_mode, :e2e)
          |> Map.put(:last_reply, nil)
          |> Map.put(:last_error, reason)
      end
    end
  end

  defp agent_stream!(ctx, %{prompt: prompt}, _meta) do
    queue = Map.get(ctx, :mock_queue, [])
    events = [{:stream, :start}]

    if queue != [] do
      agent = ctx.agent
      case Gong.MockLLM.run_chat(agent, prompt, queue) do
        {:ok, reply, updated_agent} ->
          events = events ++ [{:stream, :delta}, {:stream, :end}]
          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, reply)
          |> Map.put(:stream_events, events)
          |> Map.put(:mock_queue, [])

        {:error, reason, updated_agent} ->
          events = events ++ [{:stream, :end}]
          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, nil)
          |> Map.put(:last_error, reason)
          |> Map.put(:stream_events, events)
          |> Map.put(:mock_queue, [])
      end
    else
      ctx
      |> Map.put(:last_reply, nil)
      |> Map.put(:stream_events, events ++ [{:stream, :end}])
      |> Map.put(:mock_queue, [])
    end
  end

  defp agent_abort!(ctx, _args, _meta) do
    if ctx[:agent_pid] do
      Gong.Agent.cancel(ctx.agent_pid)
      Process.sleep(50)
    end
    ctx
  end

  defp trigger_compaction!(ctx, _args, _meta) do
    hooks = Map.get(ctx, :hooks, [])

    case Gong.HookRunner.gate(hooks, :before_session_op, [:compact, %{}]) do
      :ok ->
        ctx

      {:blocked, reason} ->
        ctx
        |> Map.put(:last_error, "Blocked by hook: #{reason}")
    end
  end

  # ── Agent 断言实现 ──

  defp assert_agent_reply!(ctx, %{contains: expected}, _meta) do
    reply = ctx.last_reply
    assert reply != nil, "Agent 未返回回复"
    decoded = unescape(expected)
    assert to_string(reply) =~ decoded,
      "期望回复包含 #{inspect(decoded)}，实际：#{inspect(reply)}"
    ctx
  end

  defp assert_tool_was_called!(ctx, %{tool: tool_name} = args, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    tool_calls = Gong.MockLLM.extract_tool_calls(strategy_state)
    matching = Enum.filter(tool_calls, fn tc -> tc.name == tool_name end)

    if times = args[:times] do
      assert length(matching) == times,
        "期望工具 #{tool_name} 被调用 #{times} 次，实际：#{length(matching)}"
    else
      assert length(matching) > 0,
        "期望工具 #{tool_name} 被调用，但未找到调用记录"
    end

    ctx
  end

  defp assert_tool_not_called!(ctx, %{tool: tool_name}, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    tool_calls = Gong.MockLLM.extract_tool_calls(strategy_state)
    matching = Enum.filter(tool_calls, fn tc -> tc.name == tool_name end)

    assert length(matching) == 0,
      "期望工具 #{tool_name} 未被调用，但找到 #{length(matching)} 次调用"

    ctx
  end

  defp assert_hook_fired!(ctx, %{event: event}, _meta) do
    # 检查 hook_events 和 telemetry_events 两个来源
    hook_events = Map.get(ctx, :hook_events, [])
    telemetry_events = Map.get(ctx, :telemetry_events, [])

    hook_match = Enum.any?(hook_events, fn e -> to_string(e) =~ event end)

    telemetry_match =
      Enum.any?(telemetry_events, fn {event_name, _measurements, _metadata} ->
        event_str = event_name |> Enum.map(&to_string/1) |> Enum.join(".")
        event_str =~ event
      end)

    assert hook_match or telemetry_match,
      "期望 hook 事件 #{event} 已触发，实际 hook_events：#{inspect(hook_events)}，telemetry：#{length(telemetry_events)} 条"
    ctx
  end

  defp assert_hook_blocked!(ctx, %{reason_contains: reason}, _meta) do
    error = Map.get(ctx, :last_error)
    assert error != nil, "期望操作被阻止，但未发现错误"
    assert to_string(error) =~ unescape(reason),
      "期望阻止原因包含 #{inspect(reason)}，实际：#{inspect(error)}"
    ctx
  end

  defp assert_stream_events!(ctx, %{sequence: sequence}, _meta) do
    events = Map.get(ctx, :stream_events, [])
    expected_types = String.split(sequence, ",") |> Enum.map(&String.trim/1)

    actual_types = Enum.map(events, fn
      {:stream, type} -> to_string(type)
      other -> to_string(other)
    end)

    assert actual_types == expected_types,
      "期望流事件序列 #{inspect(expected_types)}，实际：#{inspect(actual_types)}"

    ctx
  end

  defp assert_last_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :last_error)
    assert error != nil, "期望存在错误，但 last_error 为 nil"
    error_msg = to_string(error)
    decoded = unescape(expected)
    assert error_msg =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error_msg)}"
    ctx
  end

  defp assert_no_crash!(ctx, _args, _meta) do
    # mock 模式检查 agent 结构体存在；E2E 模式检查进程存活
    if ctx[:agent_pid] do
      assert Process.alive?(ctx.agent_pid), "Agent 进程已崩溃"
    else
      assert ctx[:agent] != nil, "Agent 结构体不存在"
    end
    ctx
  end

  # ── Hook 断言实现 ──

  defp assert_telemetry_received!(ctx, %{event: event_str} = args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])
    expected_event = event_str |> String.split(".") |> Enum.map(&String.to_atom/1)

    matching =
      Enum.filter(telemetry_events, fn {event_name, _m, _md} ->
        event_name == expected_event
      end)

    assert length(matching) > 0,
      "期望收到 telemetry 事件 #{event_str}，实际事件：#{inspect(Enum.map(telemetry_events, &elem(&1, 0)))}"

    # 可选：检查 metadata 包含特定内容
    if mc = args[:metadata_contains] do
      has_match =
        Enum.any?(matching, fn {_, _, metadata} ->
          inspect(metadata) =~ mc
        end)

      assert has_match,
        "期望 telemetry metadata 包含 #{inspect(mc)}，实际：#{inspect(Enum.map(matching, &elem(&1, 2)))}"
    end

    ctx
  end

  defp assert_hook_error_logged!(ctx, %{hook: hook_name} = args, _meta) do
    telemetry_events = Map.get(ctx, :telemetry_events, [])

    # 查找 [:gong, :hook, :error] 事件
    error_events =
      Enum.filter(telemetry_events, fn {event_name, _m, metadata} ->
        event_name == [:gong, :hook, :error] and
          inspect(metadata[:hook]) =~ hook_name
      end)

    assert length(error_events) > 0,
      "期望 hook #{hook_name} 错误已记录，实际 hook error 事件：#{inspect(telemetry_events |> Enum.filter(fn {e, _, _} -> e == [:gong, :hook, :error] end))}"

    # 可选：检查堆栈
    if args[:has_stacktrace] == true do
      has_stack =
        Enum.any?(error_events, fn {_, _, metadata} ->
          stacktrace = metadata[:stacktrace]
          is_list(stacktrace) and length(stacktrace) > 0
        end)

      assert has_stack, "期望 hook 错误包含堆栈，但未找到"
    end

    ctx
  end

  defp assert_result_content_contains!(ctx, %{text: text}, _meta) do
    # 检查 last_reply（agent 回复内容）
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(text)

    assert to_string(reply) =~ decoded,
      "期望结果包含 #{inspect(decoded)}，实际：#{inspect(reply)}"

    ctx
  end

  defp assert_result_content_not_contains!(ctx, %{text: text}, _meta) do
    reply = Map.get(ctx, :last_reply, "")
    decoded = unescape(text)

    refute to_string(reply) =~ decoded,
      "期望结果不包含 #{inspect(decoded)}，但包含了"

    ctx
  end

  defp assert_conversation_contains!(ctx, %{text: text}, _meta) do
    strategy_state = get_agent_strategy_state(ctx)
    conversation = Map.get(strategy_state, :conversation, [])
    decoded = unescape(text)

    # 在所有消息的 content 中搜索目标文本
    found =
      Enum.any?(conversation, fn msg ->
        content = msg[:content] || msg["content"] || ""
        to_string(content) =~ decoded
      end)

    assert found,
      "期望 conversation 包含 #{inspect(decoded)}，实际消息数：#{length(conversation)}，内容：#{inspect(Enum.map(conversation, fn m -> Map.get(m, :content, Map.get(m, "content", "")) end) |> Enum.take(5))}"

    ctx
  end

  # ── Telemetry 事件收集 ──

  defp collect_telemetry_events(ctx) do
    # 从进程邮箱中收集所有 telemetry 事件
    events = drain_telemetry_messages([])
    existing = Map.get(ctx, :telemetry_events, [])
    Map.put(ctx, :telemetry_events, existing ++ events)
  end

  defp drain_telemetry_messages(acc) do
    receive do
      {:telemetry_event, event_name, measurements, metadata} ->
        drain_telemetry_messages(acc ++ [{event_name, measurements, metadata}])
    after
      0 -> acc
    end
  end

  # ── Agent 状态提取辅助 ──

  defp get_agent_strategy_state(ctx) do
    if ctx[:agent_pid] do
      Gong.MockLLM.get_strategy_state(ctx.agent_pid)
    else
      agent = ctx.agent
      Jido.Agent.Strategy.State.get(agent, %{})
    end
  end

  # ── Tape GIVEN 实现 ──

  defp tape_init_given!(ctx, _args, _meta) do
    workspace = ctx.workspace
    tape_path = Path.join(workspace, "tape")
    {:ok, store} = Gong.Tape.Store.init(tape_path)

    ExUnit.Callbacks.on_exit(fn ->
      Gong.Tape.Store.close(store)
    end)

    ctx
    |> Map.put(:tape_store, store)
    |> Map.put(:tape_path, tape_path)
    |> Map.put(:tape_last_anchor, "session-start")
  end

  defp tape_append_given!(ctx, args, _meta) do
    store = ctx.tape_store
    anchor = Map.get(args, :anchor, Map.get(ctx, :tape_last_anchor, "session-start"))
    kind = args.kind
    content = unescape(args.content)

    case Gong.Tape.Store.append(store, anchor, %{kind: kind, content: content}) do
      {:ok, updated_store} ->
        Map.put(ctx, :tape_store, updated_store)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_handoff_given!(ctx, %{name: name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.handoff(store, name) do
      {:ok, _dir_name, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_anchor, name)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_fork_given!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.fork(store) do
      {:ok, fork_store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(fork_store)
          File.rm_rf(fork_store.workspace_path)
        end)

        # fork 成为活跃 store，父 store 保存为 tape_parent_store
        ctx
        |> Map.put(:tape_parent_store, store)
        |> Map.put(:tape_store, fork_store)
        |> Map.put(:fork_store, fork_store)
        |> Map.put(:tape_path, fork_store.workspace_path)
        |> Map.put(:tape_fork_path, fork_store.workspace_path)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_close_db!(ctx, _args, _meta) do
    store = ctx.tape_store
    Gong.Tape.Store.close(store)
    ctx
  end

  defp tape_restore_parent!(ctx, _args, _meta) do
    parent = Map.fetch!(ctx, :tape_parent_store)

    ctx
    |> Map.put(:tape_store, parent)
    |> Map.put(:tape_path, parent.workspace_path)
  end

  defp corrupt_jsonl!(ctx, %{path: path, line_content: line_content}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.write!(full, unescape(line_content) <> "\n", [:append])
    ctx
  end

  defp delete_file!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.rm!(full)
    ctx
  end

  defp clear_file!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    File.write!(full, "")
    ctx
  end

  # ── Tape WHEN 实现 ──

  defp tape_init_when!(ctx, _args, _meta) do
    workspace = ctx.workspace
    tape_path = Path.join(workspace, "tape")

    case Gong.Tape.Store.init(tape_path) do
      {:ok, store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(store)
        end)

        ctx
        |> Map.put(:tape_store, store)
        |> Map.put(:tape_path, tape_path)
        |> Map.put(:tape_last_anchor, "session-start")
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_append_when!(ctx, args, _meta) do
    store = ctx.tape_store
    anchor = Map.get(args, :anchor, Map.get(ctx, :tape_last_anchor, "session-start"))
    kind = args.kind
    content = unescape(args.content)

    case Gong.Tape.Store.append(store, anchor, %{kind: kind, content: content}) do
      {:ok, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_handoff_when!(ctx, %{name: name}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.handoff(store, name) do
      {:ok, _dir_name, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_anchor, name)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_between_anchors_when!(ctx, %{start: start_a, end: end_a}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.between_anchors(store, start_a, end_a) do
      {:ok, entries} ->
        ctx
        |> Map.put(:tape_query_results, entries)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_search_when!(ctx, %{query: query}, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.search(store, unescape(query)) do
      {:ok, entries} ->
        ctx
        |> Map.put(:tape_search_results, entries)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_fork_when!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.fork(store) do
      {:ok, fork_store} ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Tape.Store.close(fork_store)
          File.rm_rf(fork_store.workspace_path)
        end)

        ctx
        |> Map.put(:tape_parent_store, store)
        |> Map.put(:tape_store, fork_store)
        |> Map.put(:fork_store, fork_store)
        |> Map.put(:tape_path, fork_store.workspace_path)
        |> Map.put(:tape_fork_path, fork_store.workspace_path)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  defp tape_merge_when!(ctx, _args, _meta) do
    parent = Map.get(ctx, :tape_parent_store, ctx.tape_store)
    fork_store = ctx.fork_store

    case Gong.Tape.Store.merge(parent, fork_store) do
      {:ok, updated_parent} ->
        ctx
        |> Map.put(:tape_store, updated_parent)
        |> Map.put(:tape_path, updated_parent.workspace_path)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        # merge 失败时恢复到父工作区
        ctx
        |> Map.put(:tape_store, parent)
        |> Map.put(:tape_path, parent.workspace_path)
        |> Map.put(:tape_last_error, reason)
    end
  end

  defp tape_rebuild_index_when!(ctx, _args, _meta) do
    store = ctx.tape_store

    case Gong.Tape.Store.rebuild_index(store) do
      {:ok, updated_store} ->
        ctx
        |> Map.put(:tape_store, updated_store)
        |> Map.put(:tape_last_error, nil)

      {:error, reason} ->
        Map.put(ctx, :tape_last_error, reason)
    end
  end

  # ── Tape THEN 实现 ──

  defp assert_dir_exists!(ctx, %{path: path}, _meta) do
    full = resolve_tape_path(ctx, path)
    assert File.dir?(full), "期望目录存在: #{full}"
    ctx
  end

  defp assert_db_exists!(ctx, _args, _meta) do
    db_path = Path.join(ctx.tape_path, "index.db")
    assert File.exists?(db_path), "期望 index.db 存在: #{db_path}"
    ctx
  end

  defp assert_entry_count!(ctx, %{expected: expected}, _meta) do
    store = ctx.tape_store
    actual = Gong.Tape.Store.entry_count(store)

    assert actual == expected,
      "期望条目数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_anchor_count!(ctx, %{expected: expected}, _meta) do
    store = ctx.tape_store
    actual = Gong.Tape.Store.anchor_count(store)

    assert actual == expected,
      "期望锚点数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_jsonl_contains!(ctx, %{path: path, text: text}, _meta) do
    full = resolve_tape_path(ctx, path)
    content = File.read!(full)
    decoded = unescape(text)

    assert content =~ decoded,
      "期望 JSONL 文件 #{path} 包含 #{inspect(decoded)}，实际内容：#{String.slice(content, 0, 300)}"

    ctx
  end

  defp assert_jsonl_not_contains!(ctx, %{path: path, text: text}, _meta) do
    full = resolve_tape_path(ctx, path)
    decoded = unescape(text)

    case File.read(full) do
      {:ok, content} ->
        refute content =~ decoded,
          "期望 JSONL 文件 #{path} 不包含 #{inspect(decoded)}，但包含了"

      {:error, :enoent} ->
        # 文件不存在意味着不包含目标文本
        :ok
    end

    ctx
  end

  defp assert_query_results!(ctx, %{count: count} = args, _meta) do
    results = Map.get(ctx, :tape_query_results, [])

    assert length(results) == count,
      "期望查询结果 #{count} 条，实际：#{length(results)}"

    if text = args[:contains] do
      decoded = unescape(text)

      has_match =
        Enum.any?(results, fn entry ->
          to_string(entry.content) =~ decoded
        end)

      assert has_match,
        "期望查询结果包含 #{inspect(decoded)}"
    end

    ctx
  end

  defp assert_search_results!(ctx, %{count: count} = args, _meta) do
    results = Map.get(ctx, :tape_search_results, [])

    assert length(results) == count,
      "期望搜索结果 #{count} 条，实际：#{length(results)}"

    if text = args[:contains] do
      decoded = unescape(text)

      has_match =
        Enum.any?(results, fn entry ->
          to_string(entry.content) =~ decoded
        end)

      assert has_match,
        "期望搜索结果包含 #{inspect(decoded)}"
    end

    ctx
  end

  defp assert_tape_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :tape_last_error)
    assert error != nil, "期望 Tape 错误，但 tape_last_error 为 nil"
    decoded = unescape(expected)

    assert to_string(error) =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error)}"

    ctx
  end

  defp assert_fork_cleaned!(ctx, _args, _meta) do
    fork_path = Map.get(ctx, :tape_fork_path)
    assert fork_path != nil, "tape_fork_path 为 nil，没有记录 fork 路径"
    refute File.exists?(fork_path), "fork 工作区 #{fork_path} 应在 merge 后被清理"
    ctx
  end

  # ── Tape 路径辅助 ──

  defp resolve_tape_path(ctx, path) do
    tape_path = Map.get(ctx, :tape_path, ctx.workspace)

    if String.starts_with?(path, "/") do
      path
    else
      Path.join(tape_path, path)
    end
  end

  # ── Compaction GIVEN 实现 ──

  defp compaction_messages!(ctx, %{count: count} = args, _meta) do
    if count == 0 do
      Map.put(ctx, :compaction_messages, [])
    else
      # 生成指定数量的测试消息
      token_size = Map.get(args, :token_size, 100)
      # 中文字符约 2 tokens/字，所以每条约 token_size/2 个中文字符
      char_count = max(div(token_size, 2), 10)

      messages =
        Enum.map(1..count, fn i ->
          content = "测试消息第#{i}条" <> String.duplicate("内容", max(div(char_count - 6, 2), 1))
          %{role: "user", content: content}
        end)

      Map.put(ctx, :compaction_messages, messages)
    end
  end

  defp compaction_messages_with_system!(ctx, %{count: count}, _meta) do
    # 第一条为系统消息，其余为用户消息
    system_msg = %{role: "system", content: "你是一个AI助手。"}

    user_messages =
      Enum.map(1..(count - 1), fn i ->
        %{role: "user", content: "测试消息第#{i}条，包含一些需要较多token的中文内容用于测试压缩功能。"}
      end)

    Map.put(ctx, :compaction_messages, [system_msg | user_messages])
  end

  defp compaction_lock_acquired!(ctx, %{session_id: session_id}, _meta) do
    Gong.Compaction.Lock.acquire(session_id)

    ExUnit.Callbacks.on_exit(fn ->
      Gong.Compaction.Lock.release(session_id)
    end)

    ctx
  end

  defp compaction_summarize_fn_ok!(ctx, _args, _meta) do
    summarize_fn = fn _messages ->
      {:ok, "这是一段会话摘要，包含了之前讨论的主要内容。"}
    end

    Map.put(ctx, :compaction_summarize_fn, summarize_fn)
  end

  defp compaction_summarize_fn_fail!(ctx, _args, _meta) do
    summarize_fn = fn _messages ->
      {:error, :llm_unavailable}
    end

    Map.put(ctx, :compaction_summarize_fn, summarize_fn)
  end

  # ── Compaction WHEN 实现 ──

  defp when_estimate_tokens!(ctx, _args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    estimate = Gong.Compaction.TokenEstimator.estimate_messages(messages)

    ctx
    |> Map.put(:token_estimate, estimate)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_compact!(ctx, args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    opts = build_compact_opts(ctx, args)

    {compacted, summary} = Gong.Compaction.compact(messages, opts)

    ctx
    |> Map.put(:compacted_messages, compacted)
    |> Map.put(:compaction_summary, summary)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_compact_and_handoff!(ctx, args, _meta) do
    messages = Map.fetch!(ctx, :compaction_messages)
    tape_store = Map.fetch!(ctx, :tape_store)
    opts = build_compact_opts(ctx, args)

    {compacted, summary, updated_store} =
      Gong.Compaction.compact_and_handoff(tape_store, messages, opts)

    ctx
    |> Map.put(:compacted_messages, compacted)
    |> Map.put(:compaction_summary, summary)
    |> Map.put(:tape_store, updated_store)
    |> Map.put(:compaction_last_error, nil)
  end

  defp when_acquire_lock!(ctx, %{session_id: session_id}, _meta) do
    case Gong.Compaction.Lock.acquire(session_id) do
      :ok ->
        ExUnit.Callbacks.on_exit(fn ->
          Gong.Compaction.Lock.release(session_id)
        end)

        ctx |> Map.put(:compaction_last_error, nil)

      {:error, reason} ->
        ctx |> Map.put(:compaction_last_error, reason)
    end
  end

  defp build_compact_opts(ctx, args) do
    opts = []
    opts = if args[:max_tokens], do: [{:max_tokens, args.max_tokens} | opts], else: opts
    opts = if args[:window_size], do: [{:window_size, args.window_size} | opts], else: opts

    if fn_ref = Map.get(ctx, :compaction_summarize_fn) do
      [{:summarize_fn, fn_ref} | opts]
    else
      opts
    end
  end

  # ── Compaction THEN 实现 ──

  defp assert_token_estimate!(ctx, %{min: min, max: max}, _meta) do
    estimate = Map.fetch!(ctx, :token_estimate)

    assert estimate >= min,
      "期望 token 估算 >= #{min}，实际：#{estimate}"

    assert estimate <= max,
      "期望 token 估算 <= #{max}，实际：#{estimate}"

    ctx
  end

  defp assert_compacted!(ctx, %{message_count: expected}, _meta) do
    compacted = Map.fetch!(ctx, :compacted_messages)
    actual = length(compacted)

    assert actual == expected,
      "期望压缩后消息数=#{expected}，实际：#{actual}"

    ctx
  end

  defp assert_not_compacted!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary == nil, "期望未触发压缩，但 summary=#{inspect(summary)}"

    # 压缩后消息应与原始消息相同
    compacted = Map.get(ctx, :compacted_messages)
    original = Map.get(ctx, :compaction_messages)

    if compacted && original do
      assert length(compacted) == length(original),
        "期望消息数不变 #{length(original)}，实际：#{length(compacted)}"
    end

    ctx
  end

  defp assert_summary_exists!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary != nil, "期望 summary 不为 nil"
    assert is_binary(summary), "期望 summary 是字符串，实际：#{inspect(summary)}"
    ctx
  end

  defp assert_summary_nil!(ctx, _args, _meta) do
    summary = Map.get(ctx, :compaction_summary)
    assert summary == nil, "期望 summary 为 nil，实际：#{inspect(summary)}"
    ctx
  end

  defp assert_system_preserved!(ctx, _args, _meta) do
    compacted = Map.fetch!(ctx, :compacted_messages)

    # 检查压缩后的消息中仍包含系统消息
    has_system =
      Enum.any?(compacted, fn msg ->
        role = Map.get(msg, :role) || Map.get(msg, "role")
        to_string(role) == "system"
      end)

    assert has_system, "期望系统消息在压缩后仍然存在"
    ctx
  end

  defp assert_compaction_error!(ctx, %{error_contains: expected}, _meta) do
    error = Map.get(ctx, :compaction_last_error)
    assert error != nil, "期望压缩错误，但 compaction_last_error 为 nil"
    decoded = unescape(expected)

    assert to_string(error) =~ decoded,
      "期望错误包含 #{inspect(decoded)}，实际：#{inspect(error)}"

    ctx
  end

  defp assert_tape_has_compaction_anchor!(ctx, _args, _meta) do
    store = Map.fetch!(ctx, :tape_store)
    # 检查 anchor 数量增加（至少 2：session-start + compaction）
    anchor_count = Gong.Tape.Store.anchor_count(store)

    assert anchor_count >= 2,
      "期望至少 2 个 anchor（含 compaction），实际：#{anchor_count}"

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
