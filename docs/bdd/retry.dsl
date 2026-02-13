# Auto-Retry 自动重试 BDD 测试
# 错误分类 + 指数退避延迟

[SCENARIO: BDD-RETRY-001] TITLE: 429 错误分类为 transient TAGS: unit agent_loop
WHEN classify_error error="HTTP 429 Too Many Requests"
THEN assert_error_class expected="transient"

[SCENARIO: BDD-RETRY-002] TITLE: context overflow 分类为 context_overflow TAGS: unit agent_loop
WHEN classify_error error="prompt is too long for the context window"
THEN assert_error_class expected="context_overflow"

[SCENARIO: BDD-RETRY-003] TITLE: 指数退避延迟计算 TAGS: unit agent_loop
WHEN retry_delay attempt=0
THEN assert_delay_ms expected=1000
WHEN retry_delay attempt=2
THEN assert_delay_ms expected=4000
