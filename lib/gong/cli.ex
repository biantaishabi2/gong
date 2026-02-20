defmodule Gong.CLI do
  @moduledoc """
  Gong 命令行统一入口。

  对外入口以 `bin/gong` 为准，`mix gong.cli` 仅保留兼容迁移。

  同时提供 Session 事件流接入辅助 API（构建 command payload、提交、订阅管理）。
  """

  alias Gong.Session
  alias Gong.Session.Events
  alias Gong.CLI.SessionCmd

  @otp_min 25
  @elixir_min Version.parse!("1.14.0")
  @supported_command_types MapSet.new(["prompt", "steer"])

  @exit_ok 0
  @exit_usage 2
  @exit_runtime 10
  @exit_context 11

  @type runtime_info :: %{otp: String.t(), elixir: String.t()}
  @type command_payload :: %{
          required(:session_id) => String.t(),
          required(:command_id) => String.t(),
          required(:type) => String.t(),
          required(:args) => map(),
          required(:timestamp) => integer()
        }

  @spec main([String.t()]) :: no_return()
  def main(argv) when is_list(argv) do
    opts = [
      entry: System.get_env("GONG_ENTRY"),
      legacy_entry: System.get_env("GONG_LEGACY_ENTRY") == "1"
    ]

    argv
    |> run(opts)
    |> System.halt()
  end

  @spec run([String.t()], keyword()) :: non_neg_integer()
  def run(argv, opts \\ []) when is_list(argv) do
    with {:ok, parsed} <- parse_argv(argv),
         runtime <- runtime_info(opts),
         :ok <- validate_runtime(runtime) do
      execute(parsed, runtime, opts)
    else
      {:help, usage} ->
        maybe_warn_legacy_entry(opts, argv)
        IO.puts(usage)
        @exit_ok

      {:error, :usage, message} ->
        maybe_warn_legacy_entry(opts, argv)
        IO.puts(:stderr, message)
        @exit_usage

      {:error, :runtime, runtime, reason} ->
        maybe_warn_legacy_entry(opts, argv)
        print_runtime_error(runtime, reason)
        @exit_runtime
    end
  end

  @doc """
  构建标准 command payload。

  CLI 只生成命令载荷，不生成 event_id/seq/causation_id。
  """
  @spec build_command_payload(String.t(), String.t(), map(), keyword()) ::
          {:ok, command_payload()} | {:error, Session.error_t()}
  def build_command_payload(session_id, type, args, opts \\ []) do
    with :ok <- validate_command_session_id(session_id),
         :ok <- validate_command_type(type),
         :ok <- validate_command_args(args),
         {:ok, command_id} <-
           validate_command_id(Keyword.get(opts, :command_id, Events.generate_command_id())),
         {:ok, timestamp} <-
           validate_timestamp(Keyword.get(opts, :timestamp, System.os_time(:millisecond))) do
      {:ok,
       %{
         session_id: session_id,
         command_id: command_id,
         type: type,
         args: args,
         timestamp: timestamp
       }}
    end
  end

  @doc """
  向 Session 提交命令。

  CLI 层只做参数校验和转发，事件信封由 Session/Events 统一生成。
  """
  @spec submit_command(pid(), command_payload(), keyword()) :: :ok | {:error, Session.error_t()}
  def submit_command(session_pid, command_payload, opts \\ []) do
    with {:ok, normalized} <- normalize_command_payload(command_payload) do
      Session.submit_command(session_pid, normalized, opts)
    end
  end

  @doc """
  暴露 parse_command 给测试使用。

  解析 argv 字符串，返回解析结果。
  """
  @spec parse_command_for_test(String.t(), keyword()) ::
          {:ok, map()} | {:help, String.t()} | {:error, :usage, String.t()}
  def parse_command_for_test(argv_str, opts \\ []) when is_binary(argv_str) do
    argv = OptionParser.split(argv_str)

    {parsed_opts, args, _invalid} =
      OptionParser.parse(argv,
        strict: [cwd: :string, help: :boolean, model: :string],
        aliases: [h: :help]
      )

    merged_opts = Keyword.merge(opts, parsed_opts)
    parse_command(args, merged_opts)
  end

  @doc "注册 Session stream 订阅者（接收 {:session_event, event}）"
  @spec subscribe_session_stream(pid(), pid()) :: :ok | {:error, Session.error_t()}
  def subscribe_session_stream(session_pid, subscriber_pid) when is_pid(subscriber_pid) do
    Session.subscribe(session_pid, subscriber_pid)
  end

  def subscribe_session_stream(_session_pid, _subscriber_pid),
    do: invalid_argument("subscriber_pid 必须是进程 PID", "请传入当前消费进程的 pid")

  @doc "取消 Session stream 订阅者"
  @spec unsubscribe_session_stream(pid(), pid()) :: :ok | {:error, Session.error_t()}
  def unsubscribe_session_stream(session_pid, subscriber_pid) when is_pid(subscriber_pid) do
    Session.unsubscribe(session_pid, subscriber_pid)
  end

  def unsubscribe_session_stream(_session_pid, _subscriber_pid),
    do: invalid_argument("subscriber_pid 必须是进程 PID", "请传入已订阅进程的 pid")

  defp parse_argv(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [cwd: :string, help: :boolean, model: :string],
        aliases: [h: :help]
      )

    cond do
      opts[:help] ->
        {:help, usage_text()}

      invalid != [] ->
        invalid_args =
          invalid
          |> Enum.map(fn {name, _value} -> "--#{name}" end)
          |> Enum.join(", ")

        {:error, :usage, "不支持的参数: #{invalid_args}\n\n#{usage_text()}"}

      args == [] ->
        {:help, usage_text()}

      true ->
        parse_command(args, opts)
    end
  end

  defp parse_command(["doctor"], opts), do: {:ok, %{command: :doctor, opts: opts}}
  defp parse_command(["help"], _opts), do: {:help, usage_text()}
  defp parse_command(["--help"], _opts), do: {:help, usage_text()}

  defp parse_command(["chat" | _rest], opts) do
    {:ok, %{command: :chat, opts: opts}}
  end

  defp parse_command(["run" | rest], opts) do
    prompt = Enum.join(rest, " ")
    {:ok, %{command: :run, prompt: prompt, opts: opts}}
  end

  defp parse_command(["session", "list"], opts) do
    {:ok, %{command: :session_list, opts: opts}}
  end

  defp parse_command(["session", "restore", id], opts) do
    {:ok, %{command: :session_restore, session_id: id, opts: opts}}
  end

  defp parse_command(["cli" | rest], opts) do
    {:ok, %{command: :legacy_entry_alias, legacy_rest: rest, opts: opts}}
  end

  defp parse_command([unknown | _rest], _opts) do
    {:error, :usage, "未知命令: #{unknown}\n\n#{usage_text()}"}
  end

  defp execute(%{command: :chat, opts: command_opts}, _runtime, run_opts) do
    cwd = resolve_cwd(command_opts, run_opts)
    model = command_opts[:model]
    opts = [cwd: cwd] ++ if(model, do: [model: model], else: [])
    Gong.CLI.Chat.start(opts)
  end

  defp execute(%{command: :run, prompt: "", opts: _command_opts}, _runtime, _run_opts) do
    IO.puts(:stderr, "run 命令需要提供 prompt\n\n#{usage_text()}")
    @exit_usage
  end

  defp execute(%{command: :run, prompt: prompt, opts: command_opts}, _runtime, run_opts) do
    cwd = resolve_cwd(command_opts, run_opts)
    model = command_opts[:model]
    opts = [cwd: cwd] ++ if(model, do: [model: model], else: [])
    Gong.CLI.Run.run(prompt, opts)
  end

  defp execute(%{command: :session_list, opts: command_opts}, _runtime, run_opts) do
    cwd = resolve_cwd(command_opts, run_opts)
    tape_path = Path.join(cwd, ".gong/tape")

    case SessionCmd.list_sessions(tape_path) do
      {:ok, []} ->
        IO.puts("没有已保存的会话")

      {:ok, sessions} ->
        IO.puts("已保存的会话 (#{length(sessions)}):")

        Enum.each(sessions, fn s ->
          id = s["session_id"] || "unknown"
          saved_at = s["saved_at"]
          time_str = if saved_at, do: " (#{format_timestamp(saved_at)})", else: ""
          IO.puts("  #{id}#{time_str}")
        end)
    end

    @exit_ok
  end

  defp execute(%{command: :session_restore, session_id: id, opts: command_opts}, _runtime, run_opts) do
    cwd = resolve_cwd(command_opts, run_opts)
    tape_path = Path.join(cwd, ".gong/tape")

    case SessionCmd.restore_session(tape_path, id) do
      {:ok, snapshot} ->
        history = snapshot["history"] || []
        IO.puts("会话 #{id} 已恢复 (#{length(history)} 条消息)")

        Enum.each(history, fn entry ->
          role = entry["role"] || "?"
          content = entry["content"] || ""
          IO.puts("[#{role}] #{content}")
        end)

      {:error, reason} ->
        IO.puts(:stderr, "[错误] #{reason}")
    end

    @exit_ok
  end

  defp execute(%{command: :legacy_entry_alias, legacy_rest: rest, opts: opts}, runtime, run_opts) do
    print_deprecation_warning("gong cli", legacy_migration_cmd(rest))

    case legacy_alias_target(rest, opts) do
      {:ok, parsed} ->
        execute(parsed, runtime, run_opts)

      {:help, usage} ->
        maybe_warn_legacy_entry(run_opts, rest)
        IO.puts(usage)
        @exit_ok

      {:error, :usage, message} ->
        maybe_warn_legacy_entry(run_opts, rest)
        IO.puts(:stderr, message)
        @exit_usage
    end
  end

  defp execute(%{command: :doctor, opts: command_opts}, runtime, run_opts) do
    maybe_warn_legacy_entry(run_opts, ["doctor"])
    cwd = resolve_cwd(command_opts, run_opts)

    if project_dir?(cwd) do
      print_doctor(runtime, cwd)
      @exit_ok
    else
      print_context_error(runtime, cwd)
      @exit_context
    end
  end

  defp runtime_info(opts) do
    override = Keyword.get(opts, :runtime, %{})

    %{
      otp: Map.get(override, :otp, System.otp_release()),
      elixir: Map.get(override, :elixir, System.version())
    }
  end

  defp validate_runtime(runtime) do
    with :ok <- validate_otp(runtime.otp),
         :ok <- validate_elixir(runtime.elixir) do
      :ok
    else
      {:error, reason} -> {:error, :runtime, runtime, reason}
    end
  end

  defp validate_otp(version) when is_binary(version) do
    case Integer.parse(version) do
      {major, _rest} when major >= @otp_min -> :ok
      {major, _rest} -> {:error, {:otp_too_old, major}}
      :error -> {:error, {:otp_parse_failed, version}}
    end
  end

  defp validate_elixir(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, parsed} ->
        if Version.compare(parsed, @elixir_min) in [:gt, :eq] do
          :ok
        else
          {:error, {:elixir_too_old, version}}
        end

      :error ->
        {:error, {:elixir_parse_failed, version}}
    end
  end

  defp resolve_cwd(command_opts, run_opts) do
    command_opts[:cwd] || Keyword.get(run_opts, :cwd) || System.get_env("GONG_WORKDIR") ||
      File.cwd!()
  end

  defp project_dir?(cwd) do
    cwd
    |> Path.join("mix.exs")
    |> File.exists?()
  end

  defp maybe_warn_legacy_entry(run_opts, argv) do
    if Keyword.get(run_opts, :legacy_entry, false) do
      print_deprecation_warning(
        Keyword.get(run_opts, :entry, "mix gong.cli"),
        legacy_entry_migration_cmd(argv)
      )
    end
  end

  defp legacy_entry_migration_cmd([]), do: "bin/gong help"
  defp legacy_entry_migration_cmd(argv), do: "bin/gong #{Enum.join(argv, " ")}"

  defp print_deprecation_warning(old_entry, migration_cmd) do
    IO.puts(:stderr, "[DEPRECATION] 旧入口 `#{old_entry}` 已弃用，将在下个主版本升级为错误。")
    IO.puts(:stderr, "[DEPRECATION] 请迁移到 `#{migration_cmd}`。")
  end

  defp print_doctor(runtime, cwd) do
    IO.puts("Gong CLI 健康检查通过")
    IO.puts("工作目录: #{cwd}")
    IO.puts("运行时: OTP #{runtime.otp}, Elixir #{runtime.elixir}")
    IO.puts("分发边界: escript(开发/CI) | release(生产/稳定分发)")
    IO.puts("统一入口: bin/gong（对外）| mix run -e 'Gong.CLI.main([...])'（开发调试）")
  end

  defp print_context_error(runtime, cwd) do
    IO.puts(:stderr, "[ERROR] 当前目录不是 Elixir 项目目录（缺少 mix.exs）: #{cwd}")
    IO.puts(:stderr, "[ERROR] 运行前提: Erlang/OTP >= 25，Elixir >= 1.14")
    IO.puts(:stderr, "[ERROR] 当前运行时: OTP #{runtime.otp}，Elixir #{runtime.elixir}")
    IO.puts(:stderr, "[HINT] 请切换到包含 mix.exs 的目录，或使用 --cwd 指定项目目录。")
    IO.puts(:stderr, "[HINT] 迁移入口: bin/gong doctor")
  end

  defp print_runtime_error(runtime, reason) do
    IO.puts(:stderr, "[ERROR] 运行时依赖不满足。")
    IO.puts(:stderr, "[ERROR] 要求: Erlang/OTP >= 25，Elixir >= 1.14")
    IO.puts(:stderr, "[ERROR] 当前: OTP #{runtime.otp}，Elixir #{runtime.elixir}")
    IO.puts(:stderr, "[ERROR] 详情: #{runtime_error_reason(reason)}")
    IO.puts(:stderr, "[HINT] 请升级 Erlang/OTP 与 Elixir，或使用 include_erts=true 的 release 包。")
  end

  defp runtime_error_reason({:otp_too_old, version}), do: "OTP 版本过低（#{version}）"
  defp runtime_error_reason({:otp_parse_failed, version}), do: "无法解析 OTP 版本（#{version}）"
  defp runtime_error_reason({:elixir_too_old, version}), do: "Elixir 版本过低（#{version}）"
  defp runtime_error_reason({:elixir_parse_failed, version}), do: "无法解析 Elixir 版本（#{version}）"

  defp legacy_alias_target([], _opts), do: {:help, usage_text()}
  defp legacy_alias_target(rest, opts), do: parse_command(rest, opts)

  defp legacy_migration_cmd([]), do: "bin/gong help"
  defp legacy_migration_cmd(rest), do: "bin/gong #{Enum.join(rest, " ")}"

  defp usage_text do
    """
    用法:
      bin/gong chat [--model <provider:model>] [--cwd <path>]
      bin/gong run <prompt> [--model <provider:model>] [--cwd <path>]
      bin/gong session list [--cwd <path>]
      bin/gong session restore <session_id> [--cwd <path>]
      bin/gong doctor [--cwd <path>]
      bin/gong help

    命令:
      chat              进入交互式对话
      run <prompt>      单次执行 prompt
      session list      列出已保存的会话
      session restore   恢复指定会话
      doctor            检查运行时与项目上下文
      help              查看帮助

    运行前提:
      Erlang/OTP >= 25
      Elixir >= 1.14
    """
  end

  defp normalize_command_payload(command_payload) when is_map(command_payload) do
    with session_id when is_binary(session_id) <- payload_get(command_payload, :session_id),
         :ok <- validate_command_session_id(session_id),
         command_id when is_binary(command_id) <- payload_get(command_payload, :command_id),
         {:ok, _validated_command_id} <- validate_command_id(command_id),
         type when is_binary(type) <- payload_get(command_payload, :type),
         :ok <- validate_command_type(type),
         args when is_map(args) <- payload_get(command_payload, :args),
         :ok <- validate_command_args(args),
         timestamp when is_integer(timestamp) <- payload_get(command_payload, :timestamp),
         {:ok, _validated_timestamp} <- validate_timestamp(timestamp) do
      {:ok,
       %{
         session_id: session_id,
         command_id: command_id,
         type: type,
         args: args,
         timestamp: timestamp
       }}
    else
      _ ->
        invalid_argument(
          "command payload 不符合规范",
          "需要 session_id/command_id/type/args/timestamp 且 args.message 非空"
        )
    end
  end

  defp normalize_command_payload(_command_payload) do
    invalid_argument("command payload 必须是 map", "请传入标准 command payload map")
  end

  defp validate_command_session_id(session_id) when is_binary(session_id) do
    if String.trim(session_id) == "" do
      invalid_argument("session_id 不能为空", "请先创建 Session 并传入 session_id")
    else
      :ok
    end
  end

  defp validate_command_session_id(_session_id),
    do: invalid_argument("session_id 必须是字符串", "请传入非空字符串 session_id")

  defp validate_command_id(command_id) when is_binary(command_id) do
    if String.trim(command_id) == "" do
      invalid_argument("command_id 不能为空", "请为每条命令传入唯一 command_id")
    else
      {:ok, command_id}
    end
  end

  defp validate_command_id(_command_id),
    do: invalid_argument("command_id 必须是字符串", "请传入非空字符串 command_id")

  defp validate_command_type(type) when is_binary(type) do
    if MapSet.member?(@supported_command_types, type) do
      :ok
    else
      invalid_argument(
        "command.type 不支持: #{inspect(type)}",
        "当前支持 prompt/steer"
      )
    end
  end

  defp validate_command_type(_type),
    do: invalid_argument("command.type 必须是字符串", "请传入 prompt 或 steer")

  defp validate_command_args(args) when is_map(args) do
    message = payload_get(args, :message)

    if is_binary(message) and String.trim(message) != "" do
      :ok
    else
      invalid_argument("args.message 不能为空", "请在 args 中提供 message 字段")
    end
  end

  defp validate_command_args(_args),
    do: invalid_argument("args 必须是 map", "请传入 map 类型 args")

  defp validate_timestamp(timestamp) when is_integer(timestamp) and timestamp > 0,
    do: {:ok, timestamp}

  defp validate_timestamp(_timestamp),
    do: invalid_argument("timestamp 必须是毫秒正整数", "请传入 Unix 毫秒时间戳")

  defp payload_get(map, key), do: Events.payload_get(map, key)

  defp format_timestamp(ms) when is_integer(ms) do
    case DateTime.from_unix(ms, :millisecond) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> "#{ms}"
    end
  end

  defp format_timestamp(_), do: ""

  defp invalid_argument(message, hint) do
    {:error,
     Session.normalize_error(%{
       code: :invalid_argument,
       message: message,
       details: %{hint: hint}
     })}
  end
end
