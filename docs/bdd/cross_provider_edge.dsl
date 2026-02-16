# 上下文切换边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的跨厂商消息转换

# ══════════════════════════════════════════════
# Group 1: 跨厂商消息转换边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CROSS-ERR-001] TITLE: thinking 内容跨厂商转换为纯文本 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages_with_thinking count=2
WHEN convert_messages from="anthropic" to="openai"
THEN assert_converted_messages count=2
THEN assert_content_is_text

[SCENARIO: CROSS-ERR-002] TITLE: 同厂商不同模型切换不丢消息 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages count=5
WHEN convert_messages from="openai" to="openai"
THEN assert_converted_messages count=5

[SCENARIO: CROSS-ERR-003] TITLE: 带错误状态 assistant 消息在转换时被过滤 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages_with_error count=3
WHEN convert_messages from="anthropic" to="deepseek"
THEN assert_error_messages_filtered

# ══════════════════════════════════════════════
# Group 2: 事件一致性与流式缓冲（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: CROSS-ERR-004] TITLE: 事件/状态一致性 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN register_state_observer_hook
WHEN emit_event_with_message content="new test message"
THEN assert_observer_saw_updated_state

[SCENARIO: CROSS-ERR-005] TITLE: 流式期间 tool result 被缓冲不与 streaming 交错 TAGS: unit stream
GIVEN create_temp_dir
GIVEN cross_provider_tool_calls_message
WHEN buffer_tool_result_during_stream
THEN assert_tool_result_buffered

# ══════════════════════════════════════════════
# Group 3: pi-mono bugfix 回归覆盖（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CROSS-ERR-006] TITLE: 工具名映射 Glob 不误映射为 Ls (Pi#0138eee) TAGS: unit cross_provider regression
GIVEN create_temp_dir
GIVEN cross_provider_tool_calls_with_name tool_name="Glob"
WHEN convert_messages from="anthropic" to="openai"
THEN assert_converted_tool_name expected="Glob"

[SCENARIO: CROSS-ERR-007] TITLE: 跨 provider 转换保留 tool_call_id (Pi#7a41975) TAGS: unit cross_provider regression
GIVEN create_temp_dir
GIVEN cross_provider_tool_calls_with_id tool_call_id="call_abc123"
WHEN convert_messages from="anthropic" to="google"
THEN assert_converted_tool_call_id expected="call_abc123"

[SCENARIO: CROSS-ERR-008] TITLE: compat 检测覆盖 DeepSeek/OpenCode 域名 (Pi#4f9dedd) TAGS: unit cross_provider regression
GIVEN create_temp_dir
WHEN check_provider_compat url="https://api.deepseek.com/v1"
THEN assert_compat_detected provider="deepseek"
