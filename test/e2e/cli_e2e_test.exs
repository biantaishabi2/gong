defmodule Gong.CLI.E2ETest do
  @moduledoc """
  CLI 端到端冒烟测试 — 调用真实 LLM（Deepseek）验证完整链路。

  运行方式:
    MIX_ENV=test mix test test/e2e/cli_e2e_test.exs --include e2e
  """

  use ExUnit.Case, async: false

  @moduletag :e2e

  # 使用项目根目录作为 cwd，确保能加载 .gong/settings.json
  @project_root Path.expand("../..", __DIR__)

  @tag timeout: 60_000
  test "run 命令单次执行返回文本" do
    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        output =
          ExUnit.CaptureIO.capture_io(fn ->
            exit_code = Gong.CLI.Run.run("说一个字", cwd: @project_root)
            Process.put(:__e2e_exit_code__, exit_code)
            Process.put(:__e2e_output__, true)
          end)

        Process.put(:__e2e_stdout__, output)
      end)

    exit_code = Process.get(:__e2e_exit_code__, 1)
    stdout = Process.get(:__e2e_stdout__, "")

    assert exit_code == 0,
           "期望 exit code 0，实际：#{exit_code}\nstdout: #{String.slice(stdout, 0, 500)}\nstderr: #{String.slice(stderr, 0, 500)}"

    assert String.length(String.trim(stdout)) > 0, "期望有输出，实际为空"
  end

  @tag timeout: 60_000
  test "run 命令回答数学问题" do
    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        output =
          ExUnit.CaptureIO.capture_io(fn ->
            exit_code = Gong.CLI.Run.run("1+1等于几？只回答数字", cwd: @project_root)
            Process.put(:__e2e_exit_code__, exit_code)
          end)

        Process.put(:__e2e_stdout__, output)
      end)

    exit_code = Process.get(:__e2e_exit_code__, 1)
    stdout = Process.get(:__e2e_stdout__, "")

    assert exit_code == 0,
           "期望 exit code 0，实际：#{exit_code}\nstdout: #{String.slice(stdout, 0, 500)}\nstderr: #{String.slice(stderr, 0, 500)}"

    assert stdout =~ "2", "期望输出包含 '2'，实际：#{String.slice(stdout, 0, 200)}"
  end
end
