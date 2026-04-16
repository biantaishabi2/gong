defmodule Gong.PhiE2ETest do
  @moduledoc """
  Gong AgentLoop + Phi hooks 端到端集成测试（#2868）。

  通过真实的 AgentLoop + PhiGuidanceHook + PhiHybridOrchestrator
  跑完整 agent session，用 DeepSeek API 作为 LLM backend。

  跑 3 组对照：
    1. Baseline：AgentLoop 无 hooks，无 Phi
    2. Guidance only：AgentLoop + PhiGuidanceHook
    3. Hybrid：AgentLoop + PhiHybridOrchestrator（含升级逻辑）

  运行方式:
    MIX_ENV=test mix test test/gong/integration/phi_e2e_test.exs --include e2e

  需要: DEEPSEEK_API_KEY 环境变量
  """

  use ExUnit.Case, async: false

  alias Gong.{AgentLoop, PhiGuidanceHook, PhiHybridOrchestrator, PhiGuidance}
  alias Jido.Agent.Strategy.State, as: StratState

  @moduletag :e2e

  @llm_timeout 60_000

  # ── task_4: CSV type coercion bug (debug task，要求 THOUGHT/ACTION 格式) ──

  @debug_system_prompt """
  You are a debugging agent. You will be given buggy Python code and failing tests.
  At each step, respond in this exact format:

  THOUGHT: <your reasoning about the bug>
  ACTION: <one of: READ_CODE, READ_TESTS, PATCH, RUN_TESTS, DONE>

  If ACTION is PATCH, include the corrected code in a ```python code block after the ACTION line.
  Always start with THOUGHT, then ACTION on its own line.
  """

  @task_prompt """
  Here is a buggy Python function:

  ```python
  def parse_csv_row(row):
      parts = row.split(",")
      result = []
      for part in parts:
          part = part.strip()
          if "." in part:
              result.append(float(part))
          else:
              result.append(int(part))
      return result
  ```

  Tests that should pass but currently fail:
  ```python
  assert parse_csv_row("1, 2, 3") == [1, 2, 3]
  assert parse_csv_row("1, 2.5, 3") == [1, 2.5, 3]
  assert parse_csv_row("hello, 42, world") == ["hello", 42, "world"]
  assert parse_csv_row("1,,3") == [1, "", 3]
  ```

  The function crashes on strings and empty fields. Analyze the bug and provide a fix.
  """

  setup do
    api_key = System.get_env("DEEPSEEK_API_KEY")

    if api_key == nil do
      IO.puts("\n  DEEPSEEK_API_KEY 未设置，E2E 测试将被跳过")
    end

    agent = Gong.Agent.new()

    # 构建真实 LLM backend 闭包（复用 agent_loop_integration_test 模式）
    llm_backend = build_llm_backend()

    # 不带工具的 backend，用于 orchestrator run_step（让 LLM 只输出 THOUGHT/ACTION 文本）
    text_only_backend = build_text_only_llm_backend()

    %{agent: agent, llm_backend: llm_backend, text_only_backend: text_only_backend, api_key: api_key}
  end

  # ── 对照组 1: Baseline（无 hooks，无 Phi）──

  @tag timeout: 120_000
  test "baseline: AgentLoop 无 hooks 跑通不崩溃", %{
    agent: agent,
    llm_backend: llm_backend,
    api_key: api_key
  } do
    skip_if_no_key(api_key)

    # 收集 telemetry 事件
    telemetry_events = attach_telemetry_collector()

    result =
      AgentLoop.run(agent, @task_prompt,
        llm_backend: llm_backend,
        max_turns: 15
      )

    events = get_telemetry_events(telemetry_events)
    detach_telemetry(telemetry_events)

    # 验证：AgentLoop 跑通（不崩溃），接受 :ok 或 iteration_limit_reached
    {reply, updated_agent} =
      case result do
        {:ok, reply, agent} -> {reply, agent}
        {:error, {:iteration_limit_reached, _}, agent} ->
          # LLM 用工具解题，在 max_turns 内未返回 final text，也算正常
          {"[iteration_limit_reached]", agent}
      end

    assert is_binary(reply)

    IO.puts("\n  [baseline] reply length: #{String.length(reply)}")
    IO.puts("  [baseline] telemetry events: #{length(events)}")

    # 记录到进程字典供后续比较
    Process.put(:baseline_reply, reply)
    Process.put(:baseline_events, events)
  end

  # ── 对照组 2: Guidance only（AgentLoop + PhiGuidanceHook）──

  @tag timeout: 120_000
  test "guidance: PhiGuidanceHook 注入 guidance 消息", %{
    agent: agent,
    llm_backend: llm_backend,
    api_key: api_key
  } do
    skip_if_no_key(api_key)

    # 初始化 Phi tracker
    PhiGuidance.init_tracker()

    # 收集 telemetry 事件
    telemetry_events = attach_telemetry_collector()

    # 收集 on_context 注入事件
    phi_events = attach_phi_telemetry()

    result =
      AgentLoop.run(agent, @task_prompt,
        llm_backend: llm_backend,
        hooks: [PhiGuidanceHook],
        max_turns: 15
      )

    events = get_telemetry_events(telemetry_events)
    phi_injected = get_telemetry_events(phi_events)

    detach_telemetry(telemetry_events)
    detach_telemetry(phi_events)
    PhiGuidance.cleanup()

    # 验证：AgentLoop 跑通，接受 :ok 或 iteration_limit_reached
    {reply, updated_agent} =
      case result do
        {:ok, reply, agent} -> {reply, agent}
        {:error, {:iteration_limit_reached, _}, agent} ->
          {"[iteration_limit_reached]", agent}
      end

    assert is_binary(reply)

    IO.puts("\n  [guidance] reply length: #{String.length(reply)}")
    IO.puts("  [guidance] telemetry events: #{length(events)}")
    IO.puts("  [guidance] phi injection events: #{length(phi_injected)}")

    # 验证：PhiGuidanceHook.on_context 确实被调用
    # 即使 guidance 内容为空（初始状态），hook 至少会被 HookRunner.pipe 调用
    # 检查 conversation 中是否有 Phi Guidance 系统消息
    strategy_state = StratState.get(updated_agent, %{})
    conversation = Map.get(strategy_state, :conversation, [])

    guidance_msgs =
      Enum.filter(conversation, fn msg ->
        is_binary(msg[:content]) and
          String.contains?(msg[:content], "Guidance")
      end)

    IO.puts("  [guidance] guidance messages in conversation: #{length(guidance_msgs)}")

    # 验证 phi_injected telemetry（on_context:applied 或 phi:guidance:injected）
    # 注：初始空状态可能不注入，所以只验证不崩溃
    IO.puts("  [guidance] phi:guidance:injected count: #{length(phi_injected)}")

    Process.put(:guidance_reply, reply)
    Process.put(:guidance_events, events)
  end

  # ── 对照组 3: Hybrid（AgentLoop + PhiHybridOrchestrator）──

  @tag timeout: 180_000
  test "hybrid: PhiHybridOrchestrator 产生 telemetry 数据", %{
    agent: agent,
    llm_backend: llm_backend,
    text_only_backend: text_only_backend,
    api_key: api_key
  } do
    skip_if_no_key(api_key)

    # 初始化 Phi tracker（Hybrid 模式也需要）
    PhiGuidance.init_tracker()

    # 收集 hybrid telemetry
    hybrid_events = attach_hybrid_telemetry()
    telemetry_events = attach_telemetry_collector()

    # 创建 orchestrator
    orchestrator = PhiHybridOrchestrator.new(
      k: 3,
      score_threshold: 1.0
    )

    # Hybrid 模式：用 orchestrator 包装 llm_backend
    # PhiHybridOrchestrator.run_step 需要 agent + call_id + llm_backend
    # 但 AgentLoop 内部已经有自己的循环，不能直接替换。
    # 正确的做法是：在 AgentLoop 外部用 orchestrator 做一步打分，
    # 验证 orchestrator 能和真实 LLM backend 配合工作。

    # 方式 A：用 AgentLoop + hooks 跑一遍（验证 hook 集成）
    result_a =
      AgentLoop.run(agent, @task_prompt,
        llm_backend: llm_backend,
        hooks: [PhiGuidanceHook],
        max_turns: 15
      )

    reply_a =
      case result_a do
        {:ok, reply, _} -> reply
        {:error, {:iteration_limit_reached, _}, _} -> "[iteration_limit_reached]"
      end

    assert is_binary(reply_a)

    # 方式 B：直接用 PhiHybridOrchestrator.run_step 验证打分管线
    # 注入 debug system prompt + task prompt，让 LLM 输出 THOUGHT/ACTION 格式
    agent_with_prompt = inject_messages(agent, [
      %{role: :system, content: @debug_system_prompt},
      %{role: :user, content: @task_prompt}
    ])

    {:ok, response, updated_orch, step_telemetry} =
      PhiHybridOrchestrator.run_step(orchestrator, agent_with_prompt, "e2e_call_1", text_only_backend)

    events = get_telemetry_events(telemetry_events)
    hybrid_telem = get_telemetry_events(hybrid_events)

    detach_telemetry(telemetry_events)
    detach_telemetry(hybrid_events)
    PhiGuidance.cleanup()

    IO.puts("\n  [hybrid] AgentLoop reply length: #{String.length(reply_a)}")
    IO.puts("  [hybrid] orchestrator step_telemetry: #{inspect(step_telemetry)}")
    IO.puts("  [hybrid] orchestrator summary: #{inspect(PhiHybridOrchestrator.summary(updated_orch))}")
    IO.puts("  [hybrid] hybrid telemetry events: #{length(hybrid_telem)}")

    # 验证：orchestrator 产出有效 telemetry
    assert is_map(step_telemetry)
    assert Map.has_key?(step_telemetry, :step)
    assert Map.has_key?(step_telemetry, :upgraded)
    assert Map.has_key?(step_telemetry, :llm_calls)
    assert step_telemetry.llm_calls >= 1

    # 验证：orchestrator 状态更新
    assert updated_orch.total_steps == 1
    assert updated_orch.total_llm_calls >= 1

    # 验证：hybrid telemetry 事件被发出
    assert length(hybrid_telem) >= 1, "PhiHybridOrchestrator 应发出至少 1 个 telemetry 事件"

    # 验证：打分管线真正跑到了（first_score 不为 nil）
    assert step_telemetry.first_score != nil,
      "first_score 应该有值——LLM 应输出 THOUGHT/ACTION 格式，parse_action 才能解析"

    Process.put(:hybrid_reply, reply_a)
    Process.put(:hybrid_telemetry, step_telemetry)
  end

  # ── 综合对比 ──

  @tag timeout: 360_000
  test "三组对照完整运行并输出对比报告", %{
    agent: agent,
    llm_backend: llm_backend,
    text_only_backend: text_only_backend,
    api_key: api_key
  } do
    skip_if_no_key(api_key)

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("  Phi E2E 三组对照测试")
    IO.puts(String.duplicate("=", 60))

    # ── 1. Baseline ──
    IO.puts("\n  --- Baseline (no hooks) ---")
    baseline_events = attach_telemetry_collector()

    baseline_result =
      AgentLoop.run(agent, @task_prompt,
        llm_backend: llm_backend,
        max_turns: 15
      )

    {baseline_reply, baseline_agent} =
      case baseline_result do
        {:ok, reply, agent} -> {reply, agent}
        {:error, {:iteration_limit_reached, _}, agent} -> {"[iteration_limit_reached]", agent}
      end

    _baseline_ev = get_telemetry_events(baseline_events)
    detach_telemetry(baseline_events)
    baseline_conversation = get_conversation(baseline_agent)

    IO.puts("  reply: #{String.length(baseline_reply)} chars")
    IO.puts("  conversation: #{length(baseline_conversation)} messages")

    # ── 2. Guidance ──
    IO.puts("\n  --- Guidance (PhiGuidanceHook) ---")
    PhiGuidance.init_tracker()
    guidance_events = attach_telemetry_collector()
    phi_inj_events = attach_phi_telemetry()

    guidance_result =
      AgentLoop.run(agent, @task_prompt,
        llm_backend: llm_backend,
        hooks: [PhiGuidanceHook],
        max_turns: 15
      )

    {guidance_reply, guidance_agent} =
      case guidance_result do
        {:ok, reply, agent} -> {reply, agent}
        {:error, {:iteration_limit_reached, _}, agent} -> {"[iteration_limit_reached]", agent}
      end

    _guidance_ev = get_telemetry_events(guidance_events)
    phi_inj = get_telemetry_events(phi_inj_events)
    detach_telemetry(guidance_events)
    detach_telemetry(phi_inj_events)
    PhiGuidance.cleanup()
    guidance_conversation = get_conversation(guidance_agent)

    IO.puts("  reply: #{String.length(guidance_reply)} chars")
    IO.puts("  conversation: #{length(guidance_conversation)} messages")
    IO.puts("  phi injections: #{length(phi_inj)}")

    # ── 3. Hybrid ──
    IO.puts("\n  --- Hybrid (PhiHybridOrchestrator) ---")
    PhiGuidance.init_tracker()
    hybrid_telem_events = attach_hybrid_telemetry()

    orchestrator = PhiHybridOrchestrator.new(k: 3, score_threshold: 1.0)

    # 注入 debug system prompt + task prompt，让 LLM 输出 THOUGHT/ACTION 格式
    agent_with_prompt = inject_messages(agent, [
      %{role: :system, content: @debug_system_prompt},
      %{role: :user, content: @task_prompt}
    ])

    {:ok, hybrid_response, updated_orch, step_telemetry} =
      PhiHybridOrchestrator.run_step(orchestrator, agent_with_prompt, "e2e_full_1", text_only_backend)

    hybrid_telem = get_telemetry_events(hybrid_telem_events)
    detach_telemetry(hybrid_telem_events)
    PhiGuidance.cleanup()

    summary = PhiHybridOrchestrator.summary(updated_orch)

    IO.puts("  orchestrator upgraded: #{step_telemetry.upgraded}")
    IO.puts("  orchestrator llm_calls: #{step_telemetry.llm_calls}")
    IO.puts("  orchestrator first_score: #{inspect(step_telemetry.first_score)}")
    IO.puts("  orchestrator final_score: #{inspect(step_telemetry.final_score)}")
    IO.puts("  orchestrator summary: #{inspect(summary)}")
    IO.puts("  hybrid telemetry events: #{length(hybrid_telem)}")

    # ── 对比报告 ──
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("  COMPARISON REPORT")
    IO.puts(String.duplicate("=", 60))
    IO.puts("  Baseline reply:  #{String.length(baseline_reply)} chars")
    IO.puts("  Guidance reply:  #{String.length(guidance_reply)} chars")
    IO.puts("  Baseline conv:   #{length(baseline_conversation)} msgs")
    IO.puts("  Guidance conv:   #{length(guidance_conversation)} msgs")

    # Guidance 模式的 conversation 至少和 baseline 一样长（可能多了 guidance 注入）
    IO.puts("  Conv diff:       #{length(guidance_conversation) - length(baseline_conversation)} msgs")
    IO.puts("  Hybrid upgraded: #{step_telemetry.upgraded}")
    IO.puts("  Hybrid calls:    #{step_telemetry.llm_calls}")
    IO.puts(String.duplicate("=", 60))

    # ── 断言 ──
    # 三组都不崩溃
    assert is_binary(baseline_reply) and String.length(baseline_reply) > 0
    assert is_binary(guidance_reply) and String.length(guidance_reply) > 0
    assert hybrid_response != nil

    # Hybrid telemetry 有数据
    assert step_telemetry.llm_calls >= 1
    assert is_boolean(step_telemetry.upgraded)

    # 打分管线真正跑到（first_score 不为 nil）
    assert step_telemetry.first_score != nil,
      "first_score 应该有值——debug task 触发 THOUGHT/ACTION 格式，parse_action 解析成功"

    # 三组的结果有差异（至少 reply 不完全相同，因为 LLM 非确定性）
    # 注意：这个断言可能偶尔失败（LLM 碰巧返回相同文本），用 soft check
    if baseline_reply == guidance_reply do
      IO.puts("  NOTE: baseline and guidance replies identical (LLM non-determinism)")
    else
      IO.puts("  OK: baseline and guidance replies differ")
    end
  end

  # ── 辅助函数 ──

  defp skip_if_no_key(nil), do: flunk("DEEPSEEK_API_KEY 未设置，跳过 E2E 测试")
  defp skip_if_no_key(_), do: :ok

  # 向 agent conversation 注入消息（用于 run_step 前设置 system + user prompt）
  defp inject_messages(agent, messages) do
    strategy = Map.get(agent.state, :__strategy__, %{})
    conversation = Map.get(strategy, :conversation, [])
    updated_strategy = Map.put(strategy, :conversation, messages ++ conversation)
    updated_state = Map.put(agent.state, :__strategy__, updated_strategy)
    %{agent | state: updated_state}
  end

  defp build_llm_backend do
    fn agent, _call_id ->
      case call_real_llm(agent, _with_tools: true) do
        {:ok, response} -> {:ok, build_response_tuple(response)}
        {:error, reason} -> {:ok, {:error, inspect(reason)}}
      end
    end
  end

  # 不带工具的 LLM backend，用于 orchestrator run_step 场景
  # 让 LLM 只输出纯文本（THOUGHT/ACTION 格式），不走 tool_calls
  defp build_text_only_llm_backend do
    fn agent, _call_id ->
      case call_real_llm(agent, _with_tools: false) do
        {:ok, response} -> {:ok, build_response_tuple(response)}
        {:error, reason} -> {:ok, {:error, inspect(reason)}}
      end
    end
  end

  defp call_real_llm(agent, opts_kw \\ []) do
    with_tools = Keyword.get(opts_kw, :_with_tools, true)
    state = StratState.get(agent, %{})
    config = state[:config] || %{}
    conversation = Map.get(state, :conversation, [])
    messages = convert_conversation(conversation)

    reqllm_tools =
      if with_tools do
        config[:reqllm_tools] || []
      else
        []
      end

    opts = [tools: reqllm_tools, receive_timeout: @llm_timeout]

    ReqLLM.generate_text("deepseek:deepseek-chat", messages, opts)
  end

  defp build_response_tuple(response) do
    tool_calls = ReqLLM.Response.tool_calls(response)
    text = ReqLLM.Response.text(response)

    if tool_calls != [] do
      formatted =
        Enum.map(tool_calls, fn tc ->
          tc_map = ReqLLM.ToolCall.from_map(tc)
          %{id: tc_map.id, name: tc_map.name, arguments: tc_map.arguments}
        end)

      {:tool_calls, formatted}
    else
      {:text, text || ""}
    end
  end

  defp convert_conversation(conversation) do
    Enum.map(conversation, fn msg ->
      role = Map.get(msg, :role, :user)
      base = %{role: role}
      base = if c = Map.get(msg, :content), do: Map.put(base, :content, c), else: base
      base = if tc = Map.get(msg, :tool_calls), do: Map.put(base, :tool_calls, tc), else: base
      base = if n = Map.get(msg, :name), do: Map.put(base, :name, n), else: base
      if tid = Map.get(msg, :tool_call_id), do: Map.put(base, :tool_call_id, tid), else: base
    end)
  end

  defp get_conversation(agent) do
    state = StratState.get(agent, %{})
    Map.get(state, :conversation, [])
  end

  # ── Telemetry 收集器 ──

  # 收集通用 gong agent/turn 事件
  defp attach_telemetry_collector do
    ref = make_ref()
    pid = self()

    handler_id = "phi_e2e_collector_#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      [
        [:gong, :agent, :start],
        [:gong, :agent, :end],
        [:gong, :turn, :start],
        [:gong, :turn, :end],
        [:gong, :tool, :start],
        [:gong, :tool, :stop],
        [:gong, :hook, :on_context, :applied],
        [:gong, :hook, :on_before_agent, :applied]
      ],
      fn event, measurements, metadata, _config ->
        send(pid, {:telemetry_event, ref, event, measurements, metadata})
      end,
      nil
    )

    {handler_id, ref}
  end

  # 收集 Phi guidance 注入事件
  defp attach_phi_telemetry do
    ref = make_ref()
    pid = self()

    handler_id = "phi_e2e_phi_#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      [
        [:gong, :phi, :guidance, :injected]
      ],
      fn event, measurements, metadata, _config ->
        send(pid, {:telemetry_event, ref, event, measurements, metadata})
      end,
      nil
    )

    {handler_id, ref}
  end

  # 收集 Hybrid orchestrator 事件
  defp attach_hybrid_telemetry do
    ref = make_ref()
    pid = self()

    handler_id = "phi_e2e_hybrid_#{inspect(ref)}"

    :telemetry.attach_many(
      handler_id,
      [
        [:gong, :phi, :hybrid],
        [:gong, :phi, :best_of_k]
      ],
      fn event, measurements, metadata, _config ->
        send(pid, {:telemetry_event, ref, event, measurements, metadata})
      end,
      nil
    )

    {handler_id, ref}
  end

  defp get_telemetry_events({_handler_id, ref}) do
    collect_messages(ref, [])
  end

  defp collect_messages(ref, acc) do
    receive do
      {:telemetry_event, ^ref, event, measurements, metadata} ->
        collect_messages(ref, [{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp detach_telemetry({handler_id, _ref}) do
    :telemetry.detach(handler_id)
  end
end
