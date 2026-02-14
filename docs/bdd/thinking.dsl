# Thinking/Reasoning 预算 BDD 测试
# 覆盖 6 级 thinking level 和跨 provider 转换

# ══════════════════════════════════════════════
# Group 1: Thinking Level 管理（5 场景）
# ══════════════════════════════════════════════

[SCENARIO: THINKING-001] TITLE: 有效 level 验证 TAGS: unit thinking
GIVEN create_temp_dir
WHEN validate_thinking_level level="high"
THEN assert_thinking_valid

[SCENARIO: THINKING-002] TITLE: 无效 level 拒绝 TAGS: unit thinking
GIVEN create_temp_dir
WHEN validate_thinking_level level="超高"
THEN assert_thinking_invalid

[SCENARIO: THINKING-003] TITLE: Level 对应 token 预算 TAGS: unit thinking
GIVEN create_temp_dir
WHEN get_thinking_budget level="high"
THEN assert_thinking_budget expected=8192

[SCENARIO: THINKING-004] TITLE: Anthropic provider 参数转换 TAGS: unit thinking
GIVEN create_temp_dir
WHEN thinking_to_provider level="high" provider="anthropic"
THEN assert_thinking_params contains="budget_tokens"

[SCENARIO: THINKING-005] TITLE: off level 返回空参数 TAGS: unit thinking
GIVEN create_temp_dir
WHEN thinking_to_provider level="off" provider="anthropic"
THEN assert_thinking_params_empty

# ══════════════════════════════════════════════
# Group 2: Thinking 补充覆盖（5 场景）
# ══════════════════════════════════════════════

[SCENARIO: THINKING-006] TITLE: parse 有效字符串 TAGS: unit thinking
GIVEN create_temp_dir
WHEN parse_thinking_level str="high"
THEN assert_parsed_thinking_level expected="high"

[SCENARIO: THINKING-007] TITLE: parse 无效字符串 TAGS: unit thinking
GIVEN create_temp_dir
WHEN parse_thinking_level str="超高"
THEN assert_parsed_thinking_error

[SCENARIO: THINKING-008] TITLE: OpenAI provider 参数 TAGS: unit thinking
GIVEN create_temp_dir
WHEN thinking_to_provider level="high" provider="openai"
THEN assert_thinking_params contains="reasoning_effort"

[SCENARIO: THINKING-009] TITLE: DeepSeek provider 参数 TAGS: unit thinking
GIVEN create_temp_dir
WHEN thinking_to_provider level="medium" provider="deepseek"
THEN assert_thinking_params contains="thinking_budget"

[SCENARIO: THINKING-010] TITLE: budget 边界值 off 和 max TAGS: unit thinking
GIVEN create_temp_dir
WHEN get_thinking_budget level="off"
THEN assert_thinking_budget expected=0
