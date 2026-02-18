defmodule Gong.CLI do
  @moduledoc """
  Gong 命令行统一入口。

  对外入口以 `bin/gong` 为准，`mix gong.cli` 仅保留兼容迁移。
  """

  @otp_min 25
  @elixir_min Version.parse!("1.14.0")

  @exit_ok 0
  @exit_usage 2
  @exit_runtime 10
  @exit_context 11

  @type runtime_info :: %{otp: String.t(), elixir: String.t()}

  @spec main([String.t()]) :: no_return()
  def main(argv) when is_list(argv) do
    argv
    |> run()
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

  defp parse_argv(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [cwd: :string, help: :boolean],
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

  defp parse_command(["cli" | rest], opts) do
    {:ok, %{command: :legacy_entry_alias, legacy_rest: rest, opts: opts}}
  end

  defp parse_command([unknown | _rest], _opts) do
    {:error, :usage, "未知命令: #{unknown}\n\n#{usage_text()}"}
  end

  defp execute(%{command: :legacy_entry_alias, legacy_rest: rest, opts: opts}, runtime, run_opts) do
    print_deprecation_warning("gong cli", legacy_migration_cmd(rest))

    case legacy_alias_target(rest, opts) do
      {:ok, parsed} ->
        execute(parsed, runtime, run_opts)

      {:help, usage} ->
        IO.puts(usage)
        @exit_ok

      {:error, :usage, message} ->
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
      bin/gong doctor [--cwd <path>]
      bin/gong help

    命令:
      doctor   检查运行时与项目上下文
      help     查看帮助

    运行前提:
      Erlang/OTP >= 25
      Elixir >= 1.14
    """
  end
end
