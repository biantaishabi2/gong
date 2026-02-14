# Settings 管理 BDD 测试
# 覆盖配置文件加载、默认值、运行时修改

# ══════════════════════════════════════════════
# Group 1: Settings 管理 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: SETTINGS-001] TITLE: 无配置文件返回默认值 TAGS: unit settings
GIVEN create_temp_dir
GIVEN init_settings
WHEN get_setting key="model"
THEN assert_setting_value expected="deepseek:deepseek-chat"

[SCENARIO: SETTINGS-002] TITLE: 项目级覆盖全局 TAGS: unit settings
GIVEN create_temp_dir
GIVEN create_settings_file scope="project" content="{\"model\": \"openai:gpt-4\"}"
GIVEN init_settings
WHEN get_setting key="model"
THEN assert_setting_value expected="openai:gpt-4"

[SCENARIO: SETTINGS-003] TITLE: 运行时修改立即生效 TAGS: unit settings
GIVEN create_temp_dir
GIVEN init_settings
WHEN set_setting key="temperature" value="0.5"
WHEN get_setting key="temperature"
THEN assert_setting_value expected="0.5"

# ══════════════════════════════════════════════
# Group 2: Settings 边界补全 (4 场景)
# ══════════════════════════════════════════════

[SCENARIO: SETTINGS-004] TITLE: 不存在的 key 返回 nil TAGS: unit settings
GIVEN create_temp_dir
GIVEN init_settings
WHEN get_setting key="nonexistent_key"
THEN assert_setting_nil

[SCENARIO: SETTINGS-005] TITLE: list 返回所有默认设置 TAGS: unit settings
GIVEN create_temp_dir
GIVEN init_settings
WHEN list_settings
THEN assert_settings_list contains="model"
THEN assert_settings_list contains="temperature"

[SCENARIO: SETTINGS-006] TITLE: cleanup 清除 ETS 表 TAGS: unit settings
GIVEN create_temp_dir
GIVEN init_settings
WHEN cleanup_settings
WHEN get_setting_safe key="model"
THEN assert_setting_nil

[SCENARIO: SETTINGS-007] TITLE: 畸形 JSON 配置文件不崩溃 TAGS: unit settings
GIVEN create_temp_dir
GIVEN create_settings_file scope="project" content="not valid json{{"
GIVEN init_settings
WHEN get_setting key="model"
THEN assert_setting_value expected="deepseek:deepseek-chat"
