defmodule Gong.Integration.SessionRecoveryFlowTest do
  use ExUnit.Case, async: false

  alias Gong.AgentLoop
  alias Gong.Session

  @moduletag :integration

  test "恢复异常快照不中断，并可继续走重试成功链路" do
    {:ok, session} =
      Session.start_link(
        session_id: "session-recovery-flow",
        agent: Gong.Agent.new(),
        llm_backend_fn: fn _agent_state, _call_id -> {:ok, {:text, "ok"}} end
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    snapshot = %{
      history: "invalid-history",
      turn_cursor: "invalid-cursor",
      metadata: %{
        "session" => %{
          "model" => %{"provider" => "", "model_id" => ""},
          "thinking" => %{"level" => "超高"}
        }
      }
    }

    assert {:ok, restored} = Session.restore(session, snapshot)
    assert restored.history == []
    assert restored.turn_cursor == 0
    assert get_in(restored.metadata, ["session", "model"]) == "deepseek:deepseek-chat"
    assert get_in(restored.metadata, ["session", "thinking", "level"]) == "off"

    agent = Gong.MockLLM.init_agent()
    {backend, pid} = queue_backend([{:error, %{status: 429}}, {:text, "retry-ok"}])

    assert {:ok, "retry-ok", _agent} =
             AgentLoop.run(agent, "trigger retry",
               llm_backend: backend,
               max_turns: 5
             )

    Agent.stop(pid)
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
