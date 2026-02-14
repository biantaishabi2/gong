# Thinking 参数边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的 thinking 预算和持久化问题

# ══════════════════════════════════════════════
# Group 1: Thinking 参数边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: THINK-ERR-001] TITLE: maxTokens 自动调整为不小于 thinkingBudget TAGS: unit thinking
GIVEN create_temp_dir
WHEN get_thinking_budget level="high"
THEN assert_thinking_budget expected=8192
THEN assert_max_tokens_ge_budget

[SCENARIO: THINK-ERR-002] TITLE: 各厂商 thinking 标记统一识别 TAGS: unit thinking
GIVEN create_temp_dir
WHEN thinking_to_provider level="high" provider="anthropic"
THEN assert_thinking_params contains="budget_tokens"

[SCENARIO: THINK-ERR-003] TITLE: thinking 级别持久化含 off 状态 TAGS: unit thinking
GIVEN create_temp_dir
WHEN parse_thinking_level str="off"
THEN assert_parsed_thinking_level expected="off"
