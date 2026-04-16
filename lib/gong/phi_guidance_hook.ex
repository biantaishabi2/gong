defmodule Gong.PhiGuidanceHook do
  @moduledoc """
  Φ 引导 Hook（#2844）。

  在 AgentLoop 的 on_context 注入点，将 Φ guidance 注入 LLM conversation。
  在 on_tool_result 注入点，跟踪工具调用以更新 agent_state。

  ## 注入机制

  使用 `Gong.Hook` 的两个回调：
  - `on_context/1`：每轮 LLM 调用前，生成 guidance 并注入 conversation
  - `on_tool_result/2`：每次工具执行后，更新 Φ tracker

  ## 使用方式

      Gong.AgentLoop.run(agent, prompt, [
        llm_backend: backend,
        hooks: [Gong.PhiGuidanceHook]
      ])

  ## 关闭 guidance

  不传入此 Hook 即可关闭，不影响现有 loop 行为。
  """

  @behaviour Gong.Hook

  @impl Gong.Hook
  def on_context(messages) do
    # 从 tracker 生成 guidance
    guidance = Gong.PhiGuidance.generate()

    case Gong.PhiGuidance.format_message(guidance) do
      nil ->
        # 无 guidance（降级/空状态）→ 不修改 conversation
        messages

      guidance_msg ->
        # 发送 telemetry
        :telemetry.execute(
          [:gong, :phi, :guidance, :injected],
          %{count: 1},
          %{
            recommended: guidance.recommended_actions,
            discouraged: guidance.discouraged_actions
          }
        )

        # 注入到 conversation 末尾（最新的上下文，LLM 更关注末尾）
        messages ++ [guidance_msg]
    end
  end

  @impl Gong.Hook
  def on_tool_result(tool_atom, result) do
    # 更新 tracker
    tool_name = Atom.to_string(tool_atom)
    Gong.PhiGuidance.update_tracker(tool_name, %{}, result)

    # 不修改 result，透传
    result
  end
end
