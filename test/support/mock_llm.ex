defmodule Gong.MockLLM do
  @moduledoc """
  Mock LLM 测试基础设施。

  通过预定义响应队列驱动 AgentLoop，绕过真实 LLM/HTTP 调用。
  核心循环逻辑已提取到 Gong.AgentLoop，本模块仅管理响应队列。
  """

  @doc """
  初始化 agent（策略层），返回初始化后的 agent 结构体。
  """
  @spec init_agent() :: struct()
  def init_agent do
    Gong.Agent.new()
  end

  @doc """
  驱动完整的 ReAct 对话循环（策略层）。

  给定用户 prompt 和 mock 响应队列，自动执行：
  1. 发送 start 指令 → 获取 LLM call_id
  2. 注入 mock LLM 响应
  3. 如果是 tool_calls → 执行真实工具 → 发送 tool_result → 循环
  4. 如果是 final_answer → 返回结果

  响应队列格式：
  - `{:text, "内容"}` — final_answer
  - `{:tool_calls, [%{name: "...", arguments: %{}}]}` — 工具调用
  - `{:error, "错误信息"}` — LLM 错误

  第 4 个参数 hooks 为 Hook 模块列表，默认为空。

  返回 `{:ok, reply, agent}` 或 `{:error, reason, agent}`
  """
  @spec run_chat(struct(), String.t(), [tuple()], [module()]) ::
          {:ok, String.t(), struct()} | {:error, term(), struct()}
  def run_chat(agent, prompt, response_queue, hooks \\ [], opts \\ []) do
    # 用 Agent 进程管理响应队列，支持 llm_backend 多次调用
    {:ok, queue_pid} = Agent.start_link(fn -> response_queue end)

    llm_backend = fn _agent, _call_id ->
      response = Agent.get_and_update(queue_pid, fn
        [head | tail] -> {head, tail}
        [] -> {:queue_exhausted, []}
      end)

      case response do
        :queue_exhausted -> {:error, "response queue exhausted"}
        resp -> {:ok, resp}
      end
    end

    result =
      Gong.AgentLoop.run(agent, prompt, [
        {:llm_backend, llm_backend},
        {:hooks, hooks},
        {:max_turns, Keyword.get(opts, :max_turns, 25)},
        {:steering_config, Keyword.get(opts, :steering_config)}
        | opts
      ])

    Agent.stop(queue_pid)
    result
  end

  # ── AgentServer 辅助（用于 E2E 测试）──

  @doc "获取 agent 策略状态（从 AgentServer）"
  @spec get_strategy_state(pid()) :: map()
  def get_strategy_state(pid) do
    {:ok, server_state} = Jido.AgentServer.state(pid)
    Map.get(server_state.agent.state, :__strategy__, %{})
  end

  @doc "从策略状态提取工具调用记录"
  @spec extract_tool_calls(map()) :: [map()]
  def extract_tool_calls(strategy_state) do
    conversation = Map.get(strategy_state, :conversation, [])

    conversation
    |> Enum.flat_map(fn
      %{role: :assistant, tool_calls: tcs} when is_list(tcs) ->
        Enum.map(tcs, fn tc ->
          %{name: tc[:name] || tc["name"], arguments: tc[:arguments] || tc["arguments"] || %{}}
        end)

      _ ->
        []
    end)
  end
end
