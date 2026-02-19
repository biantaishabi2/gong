defmodule Gong.BDD.SessionL1AlignmentBDDTest do
  use ExUnit.Case, async: false

  alias Gong.AgentLoop
  alias Gong.Session

  @moduletag :bdd

  test "Given 可重试错误样本 When 执行 AgentLoop Then 命中重试并成功" do
    # Given
    agent = Gong.MockLLM.init_agent()

    error_samples = [
      {:error, %{type: "timeout", status: 400}},
      {:error, %{type: "connection_reset"}},
      {:error, %{status: 429}}
    ]

    Enum.each(error_samples, fn first_error ->
      {backend, pid} = queue_backend([first_error, {:text, "ok-after-retry"}])

      # When / Then
      assert {:ok, "ok-after-retry", _agent} =
               AgentLoop.run(agent, "retry", llm_backend: backend, max_turns: 5)

      Agent.stop(pid)
    end)
  end

  test "Given 不可重试错误样本 When 执行 AgentLoop Then 不触发重试并直接失败" do
    # Given
    agent = Gong.MockLLM.init_agent()

    error_samples = [
      {:error, %{type: "invalid_request", status: 503}},
      {:error, %{status: 400}},
      {:error, %{status: 401}}
    ]

    Enum.each(error_samples, fn first_error ->
      {backend, pid} = queue_backend([first_error, {:text, "should-not-reach"}])

      # When / Then
      assert {:error, _reason, _agent} =
               AgentLoop.run(agent, "no-retry", llm_backend: backend, max_turns: 5)

      Agent.stop(pid)
    end)
  end

  test "Given 恢复字段缺失或旧格式 When restore Then 默认回退且不中断" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-l1-bdd",
        backend: fn _message, _opts, _ctx -> {:ok, [{:chunk, "ok"}, :done]} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    # Given
    snapshot = %{
      history: [%{role: :user, content: "legacy", turn_id: 1, ts: 1}],
      turn_id: 1,
      metadata: %{
        "initial_state" => %{
          "model" => "openai/gpt-4o",
          "thinking_level" => "high"
        }
      }
    }

    # When
    assert {:ok, restored} = Session.restore(session, snapshot)

    # Then
    assert restored.turn_cursor == 1
    assert get_in(restored.metadata, ["session", "model"]) == "openai:gpt-4o"
    assert get_in(restored.metadata, ["session", "thinking", "level"]) == "high"
  end

  test "Given tool_result/空 assistant/多模态 assistant When 提取最后回复 Then 返回最后有效文本" do
    # Given
    messages = [
      %{role: :assistant, content: "第一条"},
      %{role: :tool_result, content: "tool"},
      %{role: :assistant, content: "  "},
      %{
        role: :assistant,
        content: [%{type: "image", value: "img://x"}, %{type: "text", text: "最终文本"}]
      }
    ]

    # When / Then
    assert Session.get_last_assistant_message(messages) == "最终文本"
    assert Session.get_last_assistant_message([%{role: :assistant, content: ""}]) == nil
  end

  defp queue_backend(responses) do
    {:ok, pid} = Agent.start_link(fn -> responses end)

    backend = fn _agent, _call_id ->
      response =
        Agent.get_and_update(pid, fn
          [head | tail] -> {head, tail}
          [] -> {:queue_exhausted, []}
        end)

      case response do
        :queue_exhausted -> {:error, "queue exhausted"}
        other -> {:ok, other}
      end
    end

    {backend, pid}
  end
end
