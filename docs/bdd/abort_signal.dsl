# Abort 信号传播 BDD 测试
# 覆盖 abort 信号的设置、检查、重置

# ══════════════════════════════════════════════
# Group 1: Abort 信号基本操作 (5 场景)
# ══════════════════════════════════════════════

[SCENARIO: ABORT-001] TITLE: 工具执行中 abort TAGS: integration abort
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN setup_abort_scenario after_tool=1
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo running"
GIVEN mock_llm_response response_type="text" content="工具被中止"
WHEN agent_chat prompt="执行命令"
THEN assert_no_crash

[SCENARIO: ABORT-002] TITLE: 多工具 abort 跳过后续 TAGS: integration abort
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN setup_abort_scenario after_tool=1
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo first" tool_id="tc1"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo second" tool_id="tc2" batch_with_previous="true"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo third" tool_id="tc3" batch_with_previous="true"
GIVEN mock_llm_response response_type="text" content="部分完成"
WHEN agent_chat prompt="执行三个命令"
THEN assert_no_crash

[SCENARIO: ABORT-003] TITLE: LLM 等待中 abort TAGS: integration abort
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="正常返回"
WHEN send_abort_signal
THEN assert_abort_reset
WHEN agent_chat prompt="你好"
THEN assert_no_crash

[SCENARIO: ABORT-004] TITLE: abort 后恢复 TAGS: integration abort
GIVEN create_temp_dir
GIVEN configure_agent
WHEN send_abort_signal
THEN assert_abort_reset
GIVEN mock_llm_response response_type="text" content="恢复后正常"
WHEN agent_chat prompt="恢复测试"
THEN assert_agent_reply contains="恢复后正常"
THEN assert_no_crash

[SCENARIO: ABORT-005] TITLE: Partial content 保留 TAGS: integration abort stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:已保留内容|abort:中断"
WHEN agent_stream prompt="流式中断"
THEN assert_stream_content expected="已保留内容"
THEN assert_no_crash
