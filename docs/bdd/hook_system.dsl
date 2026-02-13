# Hook 系统 BDD 测试
# 对应阶段四：事件拦截与数据变换 Hook 基础设施
# 覆盖通知型、拦截型、变换型、错误处理、注册

# ══════════════════════════════════════════════
# Group 1: 通知型 (3 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-HOOK-001] TITLE: 工具执行发 telemetry TAGS: hook telemetry
GIVEN create_temp_dir
GIVEN create_temp_file path="hello.txt" content="Hello"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.start"
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/hello.txt"
GIVEN mock_llm_response response_type="text" content="读完了"
WHEN agent_chat prompt="读文件"
THEN assert_telemetry_received event="gong.tool.start" metadata_contains="read_file"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="read_file"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-002] TITLE: Agent 循环生命周期 telemetry TAGS: hook telemetry
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN attach_telemetry_handler event="gong.agent.end"
GIVEN mock_llm_response response_type="text" content="你好"
WHEN agent_chat prompt="你好"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_telemetry_received event="gong.agent.end"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-003] TITLE: turn 事件含 tool_calls TAGS: hook telemetry
GIVEN create_temp_dir
GIVEN create_temp_file path="data.txt" content="数据"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.turn.end"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/data.txt"
GIVEN mock_llm_response response_type="text" content="完成"
WHEN agent_chat prompt="读一下"
THEN assert_telemetry_received event="gong.turn.end" metadata_contains="read_file"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 2: 拦截型 (4 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-HOOK-004] TITLE: before_tool_call 放行 TAGS: hook gate
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="内容"
GIVEN configure_agent
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/test.txt"
GIVEN mock_llm_response response_type="text" content="读到了内容"
WHEN agent_chat prompt="读文件"
THEN assert_agent_reply contains="读到了内容"
THEN assert_tool_was_called tool="read_file"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-005] TITLE: before_tool_call 阻止 TAGS: hook gate
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="BlockBash"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo hacked"
GIVEN mock_llm_response response_type="text" content="被阻止了"
WHEN agent_chat prompt="执行命令"
THEN assert_agent_reply contains="被阻止了"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-006] TITLE: 多 hook 拦截链 TAGS: hook gate
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="AllowAll"
GIVEN register_hook module="BlockBash"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo test"
GIVEN mock_llm_response response_type="text" content="链式拦截"
WHEN agent_chat prompt="执行"
THEN assert_agent_reply contains="链式拦截"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-007] TITLE: before_session_op 取消 compaction TAGS: hook gate
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="CancelCompact"
WHEN trigger_compaction
THEN assert_hook_blocked reason_contains="Blocked by hook"

# ══════════════════════════════════════════════
# Group 3: 变换型 (7 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-HOOK-008] TITLE: on_tool_result 脱敏 TAGS: hook transform
GIVEN create_temp_dir
GIVEN create_temp_file path="secret.txt" content="api_key=sk_test_AbCdEfGhIjKlMnOpQrStUvWxYz123456"
GIVEN configure_agent
GIVEN register_hook module="RedactApiKey"
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/secret.txt"
GIVEN mock_llm_response response_type="text" content="已脱敏"
WHEN agent_chat prompt="读取密钥文件"
THEN assert_agent_reply contains="已脱敏"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-009] TITLE: on_tool_result 多 hook 串联 TAGS: hook transform
GIVEN create_temp_dir
GIVEN create_temp_file path="base.txt" content="base"
GIVEN configure_agent
GIVEN configure_hooks hooks="Gong.TestHooks.PartialModify"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/base.txt"
GIVEN mock_llm_response response_type="text" content="串联完成"
WHEN agent_chat prompt="读取"
THEN assert_agent_reply contains="串联完成"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-010] TITLE: on_tool_result 部分修改 TAGS: hook transform
GIVEN create_temp_dir
GIVEN create_temp_file path="info.txt" content="some info"
GIVEN configure_agent
GIVEN register_hook module="PartialModify"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/info.txt"
GIVEN mock_llm_response response_type="text" content="部分修改完成"
WHEN agent_chat prompt="读取信息"
THEN assert_agent_reply contains="部分修改完成"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-011] TITLE: on_context 注入系统消息 TAGS: hook transform
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="InjectContext"
GIVEN attach_telemetry_handler event="gong.hook.on_context.applied"
GIVEN mock_llm_response response_type="text" content="上下文已注入"
WHEN agent_chat prompt="测试上下文"
THEN assert_agent_reply contains="上下文已注入"
THEN assert_telemetry_received event="gong.hook.on_context.applied"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-012] TITLE: on_input 变换输入 TAGS: hook transform
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="TransformInput"
GIVEN mock_llm_response response_type="text" content="输入已变换"
WHEN agent_chat prompt="原始输入"
THEN assert_agent_reply contains="输入已变换"
THEN assert_conversation_contains text="[filtered]"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-013] TITLE: on_input 短路 TAGS: hook transform
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="HandleInput"
GIVEN mock_llm_response response_type="text" content="不应到达"
WHEN agent_chat prompt="被拦截的输入"
THEN assert_result_content_not_contains text="不应到达"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-014] TITLE: on_before_agent 注入消息 TAGS: hook transform
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="InjectBeforeAgent"
GIVEN attach_telemetry_handler event="gong.hook.on_before_agent.applied"
GIVEN mock_llm_response response_type="text" content="注入完成"
WHEN agent_chat prompt="测试注入"
THEN assert_agent_reply contains="注入完成"
THEN assert_telemetry_received event="gong.hook.on_before_agent.applied"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 4: 错误处理 (3 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-HOOK-015] TITLE: hook 异常不影响后续执行 TAGS: hook error
GIVEN create_temp_dir
GIVEN create_temp_file path="safe.txt" content="安全内容"
GIVEN configure_agent
GIVEN register_hook module="CrashHook"
GIVEN attach_telemetry_handler event="gong.hook.error"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/safe.txt"
GIVEN mock_llm_response response_type="text" content="继续执行"
WHEN agent_chat prompt="读取安全文件"
THEN assert_agent_reply contains="继续执行"
THEN assert_no_crash

[SCENARIO: BDD-HOOK-016] TITLE: hook 异常有堆栈 TAGS: hook error
GIVEN create_temp_dir
GIVEN create_temp_file path="crash.txt" content="崩溃测试"
GIVEN configure_agent
GIVEN register_hook module="CrashHook"
GIVEN attach_telemetry_handler event="gong.hook.error"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/crash.txt"
GIVEN mock_llm_response response_type="text" content="有堆栈"
WHEN agent_chat prompt="读取"
THEN assert_hook_error_logged hook="CrashHook" has_stacktrace=true
THEN assert_no_crash

[SCENARIO: BDD-HOOK-017] TITLE: hook 超时不阻塞 TAGS: hook error
GIVEN create_temp_dir
GIVEN create_temp_file path="slow.txt" content="慢操作"
GIVEN configure_agent
GIVEN register_hook module="SlowHook"
GIVEN attach_telemetry_handler event="gong.hook.error"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/slow.txt"
GIVEN mock_llm_response response_type="text" content="超时后继续"
WHEN agent_chat prompt="读取慢文件"
THEN assert_agent_reply contains="超时后继续"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 5: 注册 (1 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-HOOK-018] TITLE: hook 注册后回调被调用 TAGS: hook register
GIVEN create_temp_dir
GIVEN create_temp_file path="reg.txt" content="注册测试"
GIVEN configure_agent
GIVEN register_hook module="AllowAll"
GIVEN attach_telemetry_handler event="gong.tool.start"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/reg.txt"
GIVEN mock_llm_response response_type="text" content="回调已触发"
WHEN agent_chat prompt="测试注册"
THEN assert_hook_fired event="gong.tool.start"
THEN assert_agent_reply contains="回调已触发"
THEN assert_no_crash
