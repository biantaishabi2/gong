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
