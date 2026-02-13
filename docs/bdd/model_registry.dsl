# ModelRegistry BDD 测试
# 覆盖多模型运行时切换

# ══════════════════════════════════════════════
# Group 1: ModelRegistry 基本操作 (6 场景)
# ══════════════════════════════════════════════

[SCENARIO: MODEL-001] TITLE: 默认模型配置 TAGS: unit model
GIVEN init_model_registry
THEN assert_current_model name="default"

[SCENARIO: MODEL-002] TITLE: 运行时切换 TAGS: unit model
GIVEN init_model_registry
GIVEN register_model name="model_a" provider="deepseek" model_id="deepseek-chat" api_key_env="DEEPSEEK_API_KEY"
GIVEN register_model name="model_b" provider="openai" model_id="gpt-4o" api_key_env="OPENAI_API_KEY"
WHEN switch_model name="model_b"
THEN assert_current_model name="model_b"

[SCENARIO: MODEL-003] TITLE: 无效模型回退 TAGS: unit model
GIVEN init_model_registry
WHEN switch_model name="nonexistent"
THEN assert_current_model name="default"
THEN assert_model_error error_contains="not_found"

[SCENARIO: MODEL-004] TITLE: API Key 缺失 TAGS: unit model
GIVEN init_model_registry
GIVEN register_model name="no_key" provider="openai" model_id="gpt-4o" api_key_env="GONG_TEST_NONEXISTENT_KEY_12345"
WHEN validate_model name="no_key"
THEN assert_model_error error_contains="未设置"

[SCENARIO: MODEL-005] TITLE: 多 Provider 注册 TAGS: unit model
GIVEN init_model_registry
GIVEN register_model name="ds" provider="deepseek" model_id="deepseek-chat" api_key_env="DEEPSEEK_API_KEY"
GIVEN register_model name="oai" provider="openai" model_id="gpt-4o" api_key_env="OPENAI_API_KEY"
THEN assert_model_count expected=3

[SCENARIO: MODEL-006] TITLE: E2E 真实切换 TAGS: unit model e2e
GIVEN check_e2e_provider
GIVEN init_model_registry
GIVEN register_model name="live" provider="deepseek" model_id="deepseek-chat" api_key_env="DEEPSEEK_API_KEY"
WHEN switch_model name="live"
THEN assert_current_model name="live"
