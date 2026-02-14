# Stream.Event BDD 测试
# 覆盖流式输出事件系统

# ══════════════════════════════════════════════
# Group 1: 流式输出（8 场景）
# ══════════════════════════════════════════════

[SCENARIO: STREAM-001] TITLE: 纯文本流式 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:你好|chunk:世界|chunk:！|done"
WHEN agent_stream prompt="测试流式"
THEN assert_stream_events sequence="start,delta,end"
THEN assert_stream_content expected="你好世界！"

[SCENARIO: STREAM-002] TITLE: Tool call 流式 TAGS: integration stream
GIVEN create_temp_dir
GIVEN create_temp_file path="stream.txt" content="tool_stream_test"
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/stream.txt"
GIVEN mock_llm_response response_type="text" content="流式工具调用完成"
WHEN agent_stream prompt="流式读文件"
THEN assert_tool_was_called tool="read_file"
THEN assert_stream_events sequence="start,delta,end"

[SCENARIO: STREAM-003] TITLE: 流式中断有内容 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:已收到|abort:用户中断"
WHEN agent_stream prompt="测试中断"
THEN assert_stream_events sequence="start,delta,end"
THEN assert_stream_content expected="已收到"

[SCENARIO: STREAM-004] TITLE: 空内容中断 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="abort:立即中断"
WHEN agent_stream prompt="测试空中断"
THEN assert_no_crash

[SCENARIO: STREAM-005] TITLE: 事件序列正确 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:A|chunk:B|chunk:C|done"
WHEN agent_stream prompt="序列测试"
THEN assert_stream_events sequence="start,delta,end"

[SCENARIO: STREAM-006] TITLE: 流式加 Hook TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="text" content="Hook流式测试"
WHEN agent_stream prompt="流式Hook"
THEN assert_stream_events sequence="start,delta,end"
THEN assert_agent_reply contains="Hook流式测试"
THEN assert_no_crash

[SCENARIO: STREAM-007] TITLE: 流式超时 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:开始|delay:6000|chunk:超时|done"
WHEN agent_stream prompt="超时测试"
THEN assert_no_crash

[SCENARIO: STREAM-008] TITLE: E2E 真实流 TAGS: integration stream e2e
GIVEN check_e2e_provider
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_stream prompt="1加1等于几？只回答数字"
THEN assert_stream_events sequence="start,delta,end"
THEN assert_agent_reply contains="2"

# ══════════════════════════════════════════════
# Group 2: 流式边界补充（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: STREAM-009] TITLE: 多 chunk 拼接边界 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:a|chunk:b|chunk:c|chunk:d|chunk:e|done"
WHEN agent_stream prompt="多chunk拼接"
THEN assert_stream_content expected="abcde"

[SCENARIO: STREAM-010] TITLE: 单字符 chunk 流 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:H|chunk:i|done"
WHEN agent_stream prompt="单字符"
THEN assert_stream_content expected="Hi"

[SCENARIO: STREAM-011] TITLE: Unicode chunk 流 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_stream_response chunks="chunk:你|chunk:好|chunk:世|chunk:界|done"
WHEN agent_stream prompt="Unicode流"
THEN assert_stream_content expected="你好世界"
