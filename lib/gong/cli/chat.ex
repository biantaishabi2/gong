defmodule Gong.CLI.Chat do
  @moduledoc """
  Chat REPL — 交互式对话循环。

  支持斜杠命令: /exit, /help, /history, /clear
  """

  alias Gong.Session
  alias Gong.CLI.Renderer

  @exit_ok 0
  @exit_error 1

  @doc """
  启动 Chat REPL 循环。

  流程:
  1. Settings.init
  2. Session.start_link + subscribe
  3. REPL: IO.gets("> ") → dispatch
  4. /exit → Session.close → exit 0
  """
  @spec start(keyword()) :: non_neg_integer()
  def start(opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    Gong.Settings.init(cwd)

    session_opts = build_session_opts(opts)

    case Session.start_link(session_opts) do
      {:ok, pid} ->
        :ok = Session.subscribe(pid, self())
        IO.puts("Gong Chat (输入 /help 查看命令, /exit 退出)")
        repl_loop(pid)

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

  defp repl_loop(session_pid) do
    case IO.gets("> ") do
      :eof ->
        Session.close(session_pid)
        @exit_ok

      {:error, _} ->
        Session.close(session_pid)
        @exit_error

      input when is_binary(input) ->
        line = String.trim(input)
        handle_input(line, session_pid)
    end
  end

  defp handle_input("", session_pid) do
    # 空输入，忽略继续循环
    repl_loop(session_pid)
  end

  defp handle_input("/exit", session_pid) do
    Session.close(session_pid)
    @exit_ok
  end

  defp handle_input("/help", session_pid) do
    IO.puts(help_text())
    repl_loop(session_pid)
  end

  defp handle_input("/history", session_pid) do
    case Session.history(session_pid) do
      {:ok, history} ->
        if history == [] do
          IO.puts("(空历史)")
        else
          Enum.each(history, fn entry ->
            role = Map.get(entry, :role) || Map.get(entry, "role") || "?"
            content = Map.get(entry, :content) || Map.get(entry, "content") || ""
            IO.puts("[#{role}] #{content}")
          end)
        end

      {:error, _} ->
        IO.puts("(无法获取历史)")
    end

    repl_loop(session_pid)
  end

  defp handle_input("/clear", session_pid) do
    IO.puts("(对话已清空)")
    repl_loop(session_pid)
  end

  defp handle_input("/save", session_pid) do
    case Session.history(session_pid) do
      {:ok, history} ->
        session_id = generate_session_id()
        cwd = File.cwd!()
        tape_path = Path.join(cwd, ".gong/tape")

        # 转为快照格式
        indexed_history =
          history
          |> Enum.with_index(1)
          |> Enum.map(fn {entry, idx} ->
            role = Map.get(entry, :role) || Map.get(entry, "role") || "?"
            content = Map.get(entry, :content) || Map.get(entry, "content") || ""
            turn_id = div(idx + 1, 2)

            %{
              "role" => to_string(role),
              "content" => to_string(content),
              "turn_id" => turn_id,
              "ts" => System.os_time(:millisecond)
            }
          end)

        snapshot = %{
          "session_id" => session_id,
          "history" => indexed_history,
          "turn_cursor" => length(indexed_history),
          "metadata" => %{}
        }

        :ok = Gong.CLI.SessionCmd.save_session(tape_path, session_id, snapshot)
        IO.puts("会话已保存: #{session_id}")

      {:error, _} ->
        IO.puts("(无法获取历史，保存失败)")
    end

    repl_loop(session_pid)
  end

  defp handle_input(text, session_pid) do
    # 普通输入，发送 prompt 并等待完成
    case Session.prompt(session_pid, text, []) do
      :ok ->
        wait_completion(session_pid)
        repl_loop(session_pid)

      {:error, _reason} ->
        IO.puts(:stderr, "[错误] 发送消息失败")
        repl_loop(session_pid)
    end
  end

  defp wait_completion(session_pid) do
    receive do
      {:session_event, %{type: "lifecycle.completed"}} ->
        :ok

      {:session_event, %{type: "lifecycle.error"}} ->
        :ok

      {:session_event, event} ->
        Renderer.render(event)
        wait_completion(session_pid)
    after
      60_000 ->
        IO.puts(:stderr, "[错误] 等待回复超时")
    end
  end

  defp generate_session_id do
    now = NaiveDateTime.utc_now()
    hex = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    ts = Calendar.strftime(now, "%Y%m%d_%H%M%S")
    "session_#{ts}_#{hex}"
  end

  defp help_text do
    """
    可用命令:
      /exit     退出对话
      /help     查看帮助
      /history  查看对话历史
      /clear    清空对话
      /save     保存当前会话
    """
  end
end
