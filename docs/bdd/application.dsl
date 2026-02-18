# Application 启动与监督 BDD 测试
# 覆盖 Application 启动、ETS 初始化、组件状态

# ══════════════════════════════════════════════
# Group 1: Application 启动初始化 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: APP-001] TITLE: Application 启动初始化所有组件 TAGS: integration application
GIVEN application_started
THEN assert_registry_running name="Jido.Registry"
THEN assert_registry_running name="Gong.SessionRegistry"
THEN assert_supervisor_running name="Gong.SessionSupervisor"
THEN assert_ets_table_exists name="gong_command_registry"
THEN assert_ets_table_exists name="gong_model_registry"
THEN assert_ets_table_exists name="gong_prompt_templates"

[SCENARIO: APP-002] TITLE: ETS 表已创建 TAGS: integration application
GIVEN application_started
THEN assert_ets_table_exists name="gong_command_registry"
THEN assert_ets_table_exists name="gong_model_registry"
THEN assert_ets_table_exists name="gong_prompt_templates"

[SCENARIO: APP-003] TITLE: Provider 注册成功 TAGS: integration application
GIVEN application_started
THEN assert_provider_registered name="Gong.Providers.DeepSeek"

# ══════════════════════════════════════════════
# Group 2: Application 生命周期 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: APP-004] TITLE: Application 重复启动返回已启动 TAGS: unit application
GIVEN application_started
WHEN start_application
THEN assert_application_already_started

[SCENARIO: APP-005] TITLE: Application 停止后组件清理 TAGS: integration application
GIVEN application_started
WHEN stop_application
THEN assert_no_session_processes
