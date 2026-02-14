# 跨 Provider / 多级 Resource / Command 注册 BDD 测试

# ══════════════════════════════════════════════
# Group 1: Cross-provider handoff（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CROSS-001] TITLE: 消息格式转换 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages count=3
WHEN convert_messages from="deepseek" to="openai"
THEN assert_converted_messages count=3

[SCENARIO: CROSS-002] TITLE: 切换摘要构建 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages count=5
WHEN build_handoff_summary
THEN assert_handoff_summary_not_empty

[SCENARIO: CROSS-003] TITLE: 多部分内容规范化 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_multipart_message
WHEN convert_messages from="anthropic" to="deepseek"
THEN assert_content_is_text

# ══════════════════════════════════════════════
# Group 2: Command 注册（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CMD-001] TITLE: 注册并执行自定义命令 TAGS: unit command
GIVEN create_temp_dir
WHEN init_command_registry
WHEN register_command name="hello" description="打招呼"
WHEN execute_command name="hello"
THEN assert_command_result contains="hello"

[SCENARIO: CMD-002] TITLE: 执行不存在的命令 TAGS: unit command
GIVEN create_temp_dir
WHEN init_command_registry
WHEN execute_command_expect_error name="nonexistent"
THEN assert_command_error contains="命令不存在"

[SCENARIO: CMD-003] TITLE: 列出所有命令 TAGS: unit command
GIVEN create_temp_dir
WHEN init_command_registry
WHEN register_command name="cmd_a" description="命令A"
WHEN register_command name="cmd_b" description="命令B"
THEN assert_command_count expected=2

# ══════════════════════════════════════════════
# Group 3: 边界补充（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CMD-004] TITLE: 命令存在性检查 TAGS: unit command
GIVEN create_temp_dir
WHEN init_command_registry
WHEN register_command name="exists_cmd" description="存在检查"
THEN assert_command_exists name="exists_cmd" expected="true"
THEN assert_command_exists name="nonexistent" expected="false"

[SCENARIO: CROSS-004] TITLE: 空消息列表转换 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages count=0
WHEN convert_messages from="openai" to="deepseek"
THEN assert_converted_messages count=0

[SCENARIO: CROSS-005] TITLE: 带 tool_calls 的消息转换 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_tool_calls_message
WHEN convert_messages from="openai" to="anthropic"
THEN assert_converted_messages count=1
THEN assert_converted_has_tool_calls
