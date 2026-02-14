# Provider 多 Provider 注册 BDD 测试
# 覆盖 Provider behaviour、ProviderRegistry 注册/切换/降级

# ══════════════════════════════════════════════
# Group 1: Provider 注册与切换（5 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROVIDER-001] TITLE: 注册单个 Provider TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="deepseek" module="MockProvider"
THEN assert_provider_count expected=1

[SCENARIO: PROVIDER-002] TITLE: 注册多个 Provider TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="deepseek" module="MockProvider"
WHEN register_provider name="openai" module="MockProvider"
WHEN register_provider name="anthropic" module="MockProvider"
THEN assert_provider_count expected=3

[SCENARIO: PROVIDER-003] TITLE: 切换当前 Provider TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="deepseek" module="MockProvider"
WHEN register_provider name="openai" module="MockProvider"
WHEN switch_provider name="openai"
THEN assert_current_provider expected="openai"

[SCENARIO: PROVIDER-004] TITLE: 切换不存在的 Provider TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="deepseek" module="MockProvider"
WHEN switch_provider_expect_error name="nonexistent"
THEN assert_provider_error contains="not_found"

[SCENARIO: PROVIDER-005] TITLE: 首个注册自动设为当前 TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="first_provider" module="MockProvider"
THEN assert_current_provider expected="first_provider"

# ══════════════════════════════════════════════
# Group 2: Provider 降级与配置校验（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROVIDER-006] TITLE: 降级到下一个 Provider TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="primary" module="MockProvider" priority=10
WHEN register_provider name="fallback" module="MockProvider" priority=5
WHEN provider_fallback from="primary"
THEN assert_current_provider expected="fallback"

[SCENARIO: PROVIDER-007] TITLE: 无降级目标返回错误 TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="only_one" module="MockProvider"
WHEN provider_fallback_expect_error from="only_one"
THEN assert_provider_error contains="no_fallback"

[SCENARIO: PROVIDER-008] TITLE: Provider 配置校验失败 TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider_with_invalid_config name="bad" module="MockProviderWithValidation"
THEN assert_provider_error contains="invalid"

[SCENARIO: PROVIDER-009] TITLE: Provider 列表按优先级排序 TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider name="low" module="MockProvider" priority=1
WHEN register_provider name="high" module="MockProvider" priority=10
WHEN register_provider name="mid" module="MockProvider" priority=5
THEN assert_provider_list_order expected="high,mid,low"
