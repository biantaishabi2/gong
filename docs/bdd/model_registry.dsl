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

# ══════════════════════════════════════════════
# Group 2: ModelRegistry 补全 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: MODEL-007] TITLE: current_model_string 返回 provider:model 格式 TAGS: unit model
GIVEN init_model_registry
WHEN get_model_string
THEN assert_model_string expected="deepseek:deepseek-chat"

[SCENARIO: MODEL-008] TITLE: list 返回所有注册模型 TAGS: unit model
GIVEN init_model_registry
GIVEN register_model name="alpha" provider="openai" model_id="gpt-4o" api_key_env="OPENAI_API_KEY"
WHEN list_models
THEN assert_model_list_count expected=2

[SCENARIO: MODEL-009] TITLE: cleanup 清除 ETS 表 TAGS: unit model
GIVEN init_model_registry
WHEN cleanup_model_registry
WHEN get_model_string_safe
THEN assert_model_string expected="deepseek:deepseek-chat"

# ══════════════════════════════════════════════
# Group 3: pi-mono bugfix 回归 (1 场景)
# ══════════════════════════════════════════════

[SCENARIO: MODEL-010] TITLE: 模型能力判断使用 contains 而非精确匹配 (Pi#bugfix) TAGS: unit model regression
GIVEN init_model_registry
GIVEN register_model name="vision_model" provider="openai" model_id="gpt-4o-vision" api_key_env="OPENAI_API_KEY"
WHEN check_model_capability name="vision_model" capability="vision"
THEN assert_capability_match expected="true"

# ══════════════════════════════════════════════
# Group 4: lookup_by_string — Step1 新增 (4 场景)
# ══════════════════════════════════════════════

[SCENARIO: MODEL-011] TITLE: lookup_by_string 匹配已注册模型 TAGS: unit model
GIVEN init_model_registry
GIVEN register_model name="ds" provider="deepseek" model_id="deepseek-chat" api_key_env="DEEPSEEK_API_KEY"
WHEN lookup_model_by_string model_str="deepseek:deepseek-chat"
THEN assert_lookup_ok provider="deepseek" model_id="deepseek-chat"

[SCENARIO: MODEL-012] TITLE: lookup_by_string 未注册时构造默认配置 TAGS: unit model
GIVEN init_model_registry
WHEN lookup_model_by_string model_str="anthropic:claude-3-opus"
THEN assert_lookup_ok provider="anthropic" model_id="claude-3-opus"
THEN assert_lookup_api_key_env expected="ANTHROPIC_API_KEY"

[SCENARIO: MODEL-013] TITLE: lookup_by_string 格式错误返回 error TAGS: unit model
GIVEN init_model_registry
WHEN lookup_model_by_string model_str="invalid-no-colon"
THEN assert_lookup_error error_contains="unknown_provider"

[SCENARIO: MODEL-014] TITLE: lookup_by_string 空 provider 或 model_id 返回 error TAGS: unit model
GIVEN init_model_registry
WHEN lookup_model_by_string model_str=":empty-provider"
THEN assert_lookup_error error_contains="unknown_provider"
