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

      {:then, :assert_stream_events} ->
        assert_stream_events!(ctx, args, meta)

      {:then, :assert_no_crash} ->
        assert_no_crash!(ctx, args, meta)

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

  defp register_hook!(ctx, %{module: _module}, _meta) do
    ctx
  end

  # ── Agent 操作实现 ──

  defp agent_chat!(ctx, %{prompt: prompt}, _meta) do
    queue = Map.get(ctx, :mock_queue, [])

    if queue != [] do
      # Mock 模式：策略层驱动
      agent = ctx.agent
      case Gong.MockLLM.run_chat(agent, prompt, queue) do
        {:ok, reply, updated_agent} ->
          ctx
          |> Map.put(:agent, updated_agent)
          |> Map.put(:last_reply, reply)
          |> Map.put(:last_error, nil)
          |> Map.put(:mock_queue, [])

        {:error, reason, updated_agent} ->
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
    ctx
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
    events = Map.get(ctx, :hook_events, [])
    assert Enum.any?(events, fn e -> to_string(e) =~ event end),
      "期望 hook 事件 #{event} 已触发，实际事件：#{inspect(events)}"
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

  defp assert_no_crash!(ctx, _args, _meta) do
    # mock 模式检查 agent 结构体存在；E2E 模式检查进程存活
    if ctx[:agent_pid] do
      assert Process.alive?(ctx.agent_pid), "Agent 进程已崩溃"
    else
      assert ctx[:agent] != nil, "Agent 结构体不存在"
    end
    ctx
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
