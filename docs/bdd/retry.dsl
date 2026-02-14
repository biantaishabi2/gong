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

# ── 2. 补充覆盖 ──

[SCENARIO: BDD-RETRY-004] TITLE: connection error 分类为 transient TAGS: unit agent_loop
WHEN classify_error error="connect ECONNREFUSED 127.0.0.1:443"
THEN assert_error_class expected="transient"

[SCENARIO: BDD-RETRY-005] TITLE: timeout 分类为 transient TAGS: unit agent_loop
WHEN classify_error error="request timeout after 30s"
THEN assert_error_class expected="transient"

[SCENARIO: BDD-RETRY-006] TITLE: 认证失败分类为 permanent TAGS: unit agent_loop
WHEN classify_error error="Invalid API key provided"
THEN assert_error_class expected="permanent"

[SCENARIO: BDD-RETRY-007] TITLE: should_retry transient attempt=0 返回 true TAGS: unit agent_loop
WHEN retry_should_retry error_class="transient" attempt=0
THEN assert_should_retry expected=true

[SCENARIO: BDD-RETRY-008] TITLE: should_retry transient attempt=3 返回 false TAGS: unit agent_loop
WHEN retry_should_retry error_class="transient" attempt=3
THEN assert_should_retry expected=false

[SCENARIO: BDD-RETRY-009] TITLE: should_retry permanent 返回 false TAGS: unit agent_loop
WHEN retry_should_retry error_class="permanent" attempt=0
THEN assert_should_retry expected=false
