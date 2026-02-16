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

# ══════════════════════════════════════════════
# Group 2: pi-mono bugfix 回归覆盖（1 场景）
# ══════════════════════════════════════════════

[SCENARIO: THINK-ERR-004] TITLE: thinking config 在顶层而非嵌套 config.config (Pi#289e60a) TAGS: unit thinking regression
GIVEN create_temp_dir
WHEN build_thinking_config level="high" provider="gemini"
THEN assert_thinking_config_flat key="thinking_budget"
