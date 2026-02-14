# 配置/模型注册边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的模型注册与切换边界

# ══════════════════════════════════════════════
# Group 1: 模型注册与切换（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: CONFIG-ERR-001] TITLE: 部分字段缺失时用默认值 TAGS: unit config
GIVEN create_temp_dir
GIVEN init_model_registry
GIVEN register_model_with_defaults name="minimal" provider="openai" model_id="gpt-4"
THEN assert_context_window_size name="minimal" expected=128000

[SCENARIO: CONFIG-ERR-002] TITLE: 配置热重载 TAGS: unit config
GIVEN create_temp_dir
GIVEN init_settings
GIVEN create_settings_file scope="project" content="{\"temperature\": \"0.7\"}"
WHEN reload_settings
THEN assert_setting_value key="temperature" expected="0.7"

[SCENARIO: CONFIG-ERR-003] TITLE: 空数组配置的语义正确 TAGS: unit config
GIVEN create_temp_dir
GIVEN init_settings
GIVEN set_config_empty_array key="allowed_tools"
THEN assert_config_blocks_all key="allowed_tools"

# ══════════════════════════════════════════════
# Group 2: 提示词与验证（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: CONFIG-ERR-004] TITLE: 系统提示词组装完整 TAGS: unit config
GIVEN create_temp_dir
WHEN build_system_prompt
THEN assert_prompt_contains_context
THEN assert_prompt_contains_time
THEN assert_prompt_contains_cwd

[SCENARIO: CONFIG-ERR-005] TITLE: 验证不存在的模型返回错误 TAGS: unit config
GIVEN create_temp_dir
GIVEN init_model_registry
WHEN validate_model name="nonexistent_xyz"
THEN assert_model_error error_contains="未注册"
