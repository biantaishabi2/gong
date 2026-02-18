defmodule Gong.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @project_root File.cwd!()
  @bin_gong Path.join(@project_root, "bin/gong")
  @bin_gong_cli Path.join(@project_root, "bin/gong-cli")

  test "项目目录内 doctor 在不同入口配置下输出与退出码一致" do
    {output_bin, exit_bin} =
      run_script(@bin_gong, ["doctor"], cd: @project_root)

    {output_mix, exit_mix} =
      run_mix_main(["doctor"],
        cd: @project_root
      )

    assert exit_bin == 0
    assert exit_mix == 0
    assert normalize_cli_output(output_bin) == normalize_cli_output(output_mix)
  end

  test "非 Elixir 项目目录执行 doctor 返回分层错误提示" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "gong-cli-no-mix-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    {output, exit_code} =
      run_script(@bin_gong, ["doctor"], cd: tmp_dir)

    assert exit_code == 11
    assert output =~ "缺少 mix.exs"
    assert output =~ tmp_dir
    assert output =~ "Erlang/OTP >= 25"
    assert output =~ "Elixir >= 1.14"
  end

  test "旧入口兼容路径可用且输出 deprecation warning" do
    {output, exit_code} =
      run_script(@bin_gong_cli, ["doctor"], cd: @project_root)

    assert exit_code == 0
    assert output =~ "Gong CLI 健康检查通过"
    assert output =~ "[DEPRECATION]"
    assert output =~ "旧入口 `bin/gong-cli` 已弃用"
    assert output =~ "bin/gong doctor"
  end

  test "旧入口子命令 help 语义保持一致" do
    {stdout, stderr, exit_code} =
      run_cli(["cli", "help"],
        cwd: @project_root
      )

    assert exit_code == 0
    assert stdout =~ "用法:"
    assert stderr =~ "[DEPRECATION]"
    assert stderr =~ "bin/gong help"
  end

  test "旧入口子命令 unknown 返回 usage 错误" do
    {_stdout, stderr, exit_code} =
      run_cli(["cli", "unknown"],
        cwd: @project_root
      )

    assert exit_code == 2
    assert stderr =~ "[DEPRECATION]"
    assert stderr =~ "未知命令: unknown"
  end

  test "依赖版本不足时官方入口返回运行时错误码与修复指引" do
    {output, exit_code} =
      run_script(@bin_gong, ["doctor"],
        cd: @project_root,
        env: [
          {"GONG_RUNTIME_OTP_OVERRIDE", "24"},
          {"GONG_RUNTIME_ELIXIR_OVERRIDE", "1.13.4"}
        ]
      )

    assert exit_code == 10
    assert output =~ "运行时依赖不满足"
    assert output =~ "Erlang/OTP >= 25"
    assert output =~ "Elixir >= 1.14"
    assert output =~ "include_erts=true 的 release 包"
  end

  defp run_cli(argv, opts) do
    parent = self()

    stdout =
      capture_io(:stdio, fn ->
        exit_code = Gong.CLI.run(argv, opts)
        send(parent, {:stdout_exit_code, exit_code})
      end)

    stderr =
      capture_io(:stderr, fn ->
        exit_code = Gong.CLI.run(argv, opts)
        send(parent, {:stderr_exit_code, exit_code})
      end)

    stdout_exit_code =
      receive do
        {:stdout_exit_code, value} -> value
      after
        1_000 -> flunk("未收到 stdout 侧 CLI 退出码")
      end

    stderr_exit_code =
      receive do
        {:stderr_exit_code, value} -> value
      after
        1_000 -> flunk("未收到 stderr 侧 CLI 退出码")
      end

    assert stdout_exit_code == stderr_exit_code

    {stdout, stderr, stdout_exit_code}
  end

  defp run_script(script, args, opts) do
    command_opts =
      opts
      |> Keyword.merge(stderr_to_stdout: true)
      |> Keyword.update(:env, [{"MIX_ENV", "test"}], &[{"MIX_ENV", "test"} | &1])

    System.cmd("bash", [script | args], command_opts)
  end

  defp run_mix_main(args, opts) do
    command_opts =
      opts
      |> Keyword.merge(stderr_to_stdout: true)
      |> Keyword.update(:env, [{"MIX_ENV", "test"}], &[{"MIX_ENV", "test"} | &1])

    System.cmd("mix", ["run", "-e", "Gong.CLI.main(System.argv())", "--" | args], command_opts)
  end

  defp normalize_cli_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, ["Compiling ", "Generated "]))
    |> Enum.join("\n")
  end
end
