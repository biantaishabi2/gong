defmodule Gong.CLI.Run do
  @moduledoc """
  单次执行模式 — 发送一个 prompt，等待完成后退出。
  """

  alias Gong.Session
  alias Gong.CLI.Renderer

  @exit_ok 0
  @exit_error 1

  @doc """
  执行单次 prompt 并返回 exit code。

  流程:
  1. Settings.init
  2. Session.start_link
  3. subscribe 当前进程
  4. prompt
  5. receive_loop 渲染事件
  6. lifecycle.completed → 退出
  """
  @spec run(String.t(), keyword()) :: non_neg_integer()
  def run(prompt, opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    Gong.Settings.init(cwd)

    session_opts = build_session_opts(opts)

    case Session.start_link(session_opts) do
      {:ok, pid} ->
        :ok = Session.subscribe(pid, self())
        :ok = Session.prompt(pid, prompt, [])
        exit_code = receive_loop(pid)
        Session.close(pid)
        exit_code

      {:error, _reason} ->
        IO.puts(:stderr, "[错误] 无法启动 Session")
        @exit_error
    end
  end

  defp build_session_opts(opts) do
    session_opts = []

    # 如果显式传入 llm_backend_fn，优先使用（测试 mock）
    if llm_backend_fn = Keyword.get(opts, :llm_backend_fn) do
      agent = Keyword.get(opts, :agent, Gong.Agent.new())
      session_opts |> Keyword.put(:agent, agent) |> Keyword.put(:llm_backend_fn, llm_backend_fn)
    else
      # 传 model 给 Session，由 Session 创建持久 Agent
      model = Keyword.get(opts, :model) || Gong.Settings.get("model")

      if model do
        Keyword.put(session_opts, :model, model)
      else
        session_opts
      end
    end
  end

  defp receive_loop(session_pid) do
    receive do
      {:session_event, %{type: "lifecycle.completed"}} ->
        @exit_ok

      {:session_event, %{type: type} = event}
      when type in ["error.stream", "error.runtime"] ->
        Renderer.render(event)
        # 继续等待 lifecycle.completed
        receive_loop(session_pid)

      {:session_event, %{type: "lifecycle.error"}} ->
        @exit_error

      {:session_event, event} ->
        Renderer.render(event)
        receive_loop(session_pid)
    after
      60_000 ->
        IO.puts(:stderr, "[错误] 执行超时")
        @exit_error
    end
  end
end
