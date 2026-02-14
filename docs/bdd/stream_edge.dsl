# 流式解析边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的流式解析容错

# ══════════════════════════════════════════════
# Group 1: 流式容错（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: STREAM-ERR-001] TITLE: 流中途中断返回部分结果 TAGS: integration stream
GIVEN create_temp_dir
GIVEN configure_agent model="mock"
GIVEN mock_stream_response chunks="hello|world|__INTERRUPT__"
WHEN agent_stream prompt="test"
THEN assert_partial_content contains="hello"

[SCENARIO: STREAM-ERR-002] TITLE: 增量 JSON 在 key 截断位置的容错 TAGS: unit partial_json
GIVEN create_temp_dir
WHEN partial_json_parse input="{\"name\": \"val"
THEN assert_partial_json_field key="name" expected="val"

[SCENARIO: STREAM-ERR-003] TITLE: 工具调用流式参数完整组装 TAGS: unit stream
GIVEN create_temp_dir
WHEN stream_tool_chunks tool_name="tool_bash" chunks="{\"comm|and\": \"echo|hello\"}"
THEN assert_tool_event_sequence sequence="tool_start,tool_delta,tool_delta,tool_delta,tool_end"

# ══════════════════════════════════════════════
# Group 2: 事件序列验证（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: STREAM-ERR-004] TITLE: Hook/命令在活跃流式期间执行的并发安全 TAGS: unit stream
GIVEN create_temp_dir
WHEN start_mock_stream
WHEN execute_hook_during_stream hook_module="AllowAll"
THEN assert_no_race_condition

[SCENARIO: STREAM-ERR-005] TITLE: 缺少 start 的事件序列被拒绝 TAGS: unit stream
GIVEN create_temp_dir
WHEN validate_stream_events types="text_delta,text_end"
THEN assert_sequence_invalid
