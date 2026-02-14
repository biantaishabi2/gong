defmodule Gong.Tools.Bash do
  @moduledoc """
  命令执行 Action。

  通过 Port 执行 bash 命令，支持超时控制、进程树杀死、滚动缓冲区。
  截断策略：tail（保留末尾）。
  """

  use Jido.Action,
    name: "bash",
    description: "执行 shell 命令",
    schema: [
      command: [type: :string, required: true, doc: "要执行的命令"],
      timeout: [type: :non_neg_integer, default: 120, doc: "超时秒数"],
      cwd: [type: :string, doc: "工作目录"]
    ]

  @max_output_bytes 50_000
  @max_output_lines 2000
  @max_buffer_bytes 102_400

  @impl true
  def run(params, _context) do
    with :ok <- validate_command(params.command),
         {:ok, cwd} <- resolve_cwd(params[:cwd]) do
      execute(params.command, params[:timeout] || 120, cwd)
    end
  end

  defp validate_command(nil), do: {:error, "command is required"}
  defp validate_command(""), do: {:error, "command cannot be empty"}
  defp validate_command(cmd) when not is_binary(cmd), do: {:error, "command must be a string"}
  defp validate_command(_), do: :ok

  defp resolve_cwd(nil), do: {:ok, nil}
  defp resolve_cwd(""), do: {:ok, nil}

  defp resolve_cwd("~/" <> rest) do
    path = Path.join(System.user_home!(), rest) |> Path.expand()
    check_cwd(path)
  end

  defp resolve_cwd(path) do
    check_cwd(Path.expand(path))
  end

  defp check_cwd(path) do
    cond do
      not File.exists?(path) ->
        {:error, "#{path}: No such file or directory (ENOENT)"}

      not File.dir?(path) ->
        {:error, "#{path}: Not a directory"}

      true ->
        {:ok, path}
    end
  end

  # ── 命令执行 ──

  defp execute(command, timeout_sec, cwd) do
    port_opts = build_port_opts(cwd)
    timeout_ms = timeout_sec * 1000

    try do
      port = Port.open({:spawn_executable, bash_path()}, [{:args, ["-c", command]} | port_opts])

      os_pid =
        case Port.info(port, :os_pid) do
          {:os_pid, pid} -> pid
          nil -> nil
        end

      collect_output(port, os_pid, timeout_ms)
    rescue
      e in ErlangError ->
        {:error, "Failed to spawn command: #{inspect(e)}"}
    end
  end

  defp bash_path do
    System.find_executable("bash") || "/bin/bash"
  end

  defp build_port_opts(cwd) do
    base = [:binary, :exit_status, :use_stdio, :stderr_to_stdout, :hide]
    if cwd, do: [{:cd, String.to_charlist(cwd)} | base], else: base
  end

  # ── 输出收集（deadline 模式 + 滚动缓冲） ──

  defp collect_output(port, os_pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    state = %{
      chunks: [],
      buf_bytes: 0,
      total_bytes: 0,
      temp_path: nil
    }

    do_collect(port, os_pid, deadline, state, timeout_ms)
  end

  defp do_collect(port, os_pid, deadline, state, original_timeout_ms) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      # 超时：杀进程树
      kill_process_tree(os_pid)
      safe_close_port(port)
      output = build_output(state)
      timeout_sec = div(original_timeout_ms, 1000)

      {:ok,
       Gong.ToolResult.new(
         output <> "\n\nCommand timed out after #{timeout_sec} seconds",
         %{exit_code: nil, timed_out: true, truncated: state.total_bytes > @max_output_bytes, temp_file: state.temp_path}
       )}
    else
      receive do
        {^port, {:data, data}} ->
          state = ingest_chunk(state, data)
          do_collect(port, os_pid, deadline, state, original_timeout_ms)

        {^port, {:exit_status, exit_code}} ->
          output = build_output(state)
          format_result(output, exit_code, state)
      after
        min(remaining, 200) ->
          do_collect(port, os_pid, deadline, state, original_timeout_ms)
      end
    end
  end

  # ── 滚动缓冲 + 临时文件 ──

  defp ingest_chunk(state, data) do
    chunk_size = byte_size(data)
    new_total = state.total_bytes + chunk_size

    # 当总输出超过阈值时创建临时文件
    temp_path =
      if new_total > @max_output_bytes and state.temp_path == nil do
        path = Path.join(System.tmp_dir!(), "gong_bash_#{:erlang.unique_integer([:positive])}.out")
        buffered = state.chunks |> IO.iodata_to_binary()
        File.write!(path, buffered <> data)
        path
      else
        if state.temp_path, do: File.write!(state.temp_path, data, [:append])
        state.temp_path
      end

    # 加入缓冲区（prepend，O(1)）
    new_chunks = [data | state.chunks]
    new_buf = state.buf_bytes + chunk_size

    # 超出缓冲限制时裁剪旧数据
    {trimmed, trimmed_bytes} =
      if new_buf > @max_buffer_bytes do
        trim_buffer(new_chunks, new_buf)
      else
        {new_chunks, new_buf}
      end

    %{state | chunks: trimmed, buf_bytes: trimmed_bytes, total_bytes: new_total, temp_path: temp_path}
  end

  defp trim_buffer(chunks, buf_bytes) when buf_bytes <= @max_buffer_bytes, do: {chunks, buf_bytes}

  defp trim_buffer(chunks, buf_bytes) do
    # chunks 是 newest-first；反转后丢弃最老的
    [oldest | rest] = Enum.reverse(chunks)
    trim_buffer(Enum.reverse(rest), buf_bytes - byte_size(oldest))
  end

  # ── 结果格式化 ──

  defp format_result(output, 0, state) do
    {:ok,
     Gong.ToolResult.new(
       output,
       %{exit_code: 0, timed_out: false, truncated: state.total_bytes > @max_output_bytes, temp_file: state.temp_path}
     )}
  end

  defp format_result(output, exit_code, state) do
    content =
      if output == "" do
        "Command exited with code #{exit_code}"
      else
        output <> "\n\nCommand exited with code #{exit_code}"
      end

    {:ok,
     Gong.ToolResult.new(
       content,
       %{exit_code: exit_code, timed_out: false, truncated: state.total_bytes > @max_output_bytes, temp_file: state.temp_path}
     )}
  end

  # ── 输出构建 + 截断 ──

  defp build_output(%{chunks: chunks, total_bytes: total_bytes}) do
    raw = chunks |> Enum.reverse() |> IO.iodata_to_binary()
    raw = String.trim_trailing(raw, "\n")

    if total_bytes > @max_output_bytes do
      result = Gong.Truncate.truncate(raw, :tail, max_bytes: @max_output_bytes)
      result.content <> "\n[原始 #{total_bytes} 字节]"
    else
      maybe_truncate_lines(raw)
    end
  end

  defp maybe_truncate_lines(output) do
    lines = String.split(output, "\n")

    if length(lines) > @max_output_lines do
      kept = Enum.take(lines, -@max_output_lines)
      omitted = length(lines) - @max_output_lines
      "[... #{omitted} lines omitted ...]\n" <> Enum.join(kept, "\n")
    else
      output
    end
  end

  # ── 进程树杀死 ──

  defp kill_process_tree(nil), do: :ok

  defp kill_process_tree(os_pid) do
    # 负 PID = 发送信号给整个进程组
    case System.cmd("kill", ["-9", "-#{os_pid}"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> kill_single(os_pid)
    end
  rescue
    _ -> kill_single(os_pid)
  end

  defp kill_single(os_pid) do
    System.cmd("kill", ["-9", "#{os_pid}"], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp safe_close_port(port) do
    if Port.info(port) != nil do
      Port.close(port)
    end
  rescue
    _ -> :ok
  end
end
