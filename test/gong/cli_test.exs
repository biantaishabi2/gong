defmodule Gong.CLITest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @project_root File.cwd!()

  test "项目目录内 doctor 在不同入口配置下输出与退出码一致" do
    {stdout_bin, stderr_bin, exit_bin} =
      run_cli(["doctor"],
        entry: "bin/gong",
        cwd: @project_root
      )

    {stdout_mix, stderr_mix, exit_mix} =
      run_cli(["doctor"],
        entry: "mix run -e 'Gong.CLI.main([\"doctor\"])'",
        cwd: @project_root
      )

    assert exit_bin == 0
    assert exit_mix == 0
    assert stderr_bin == ""
    assert stderr_mix == ""
    assert stdout_bin == stdout_mix
  end

  test "非 Elixir 项目目录执行 doctor 返回分层错误提示" do
    tmp_dir =
      Path.join(System.tmp_dir!(), "gong-cli-no-mix-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    {_stdout, stderr, exit_code} =
      run_cli(["doctor"],
        cwd: tmp_dir
      )

    assert exit_code == 11
    assert stderr =~ "缺少 mix.exs"
    assert stderr =~ "Erlang/OTP >= 25"
    assert stderr =~ "Elixir >= 1.14"
  end

  test "旧入口兼容路径可用且输出 deprecation warning" do
    {stdout, stderr, exit_code} =
      run_cli(["doctor"],
        cwd: @project_root,
        entry: "mix gong.cli",
        legacy_entry: true
      )

    assert exit_code == 0
    assert stdout =~ "Gong CLI 健康检查通过"
    assert stderr =~ "[DEPRECATION]"
    assert stderr =~ "bin/gong doctor"
  end

  test "依赖版本不足时返回运行时错误码与修复指引" do
    {_stdout, stderr, exit_code} =
      run_cli(["doctor"],
        cwd: @project_root,
        runtime: %{otp: "24", elixir: "1.13.4"}
      )

    assert exit_code == 10
    assert stderr =~ "运行时依赖不满足"
    assert stderr =~ "Erlang/OTP >= 25"
    assert stderr =~ "Elixir >= 1.14"
    assert stderr =~ "include_erts=true 的 release 包"
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
end
