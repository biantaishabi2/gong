# 工具配置系统 BDD 场景
# 覆盖 Gong.ToolConfig 的预设、运行时切换、校验

[SCENARIO: TOOLCFG-001] TITLE: 默认激活 4 个核心工具 TAGS: unit tool_config
GIVEN init_tool_config
WHEN get_active_tools
THEN assert_active_tool_count expected=4
THEN assert_active_tool_contains tool="read"
THEN assert_active_tool_contains tool="write"
THEN assert_active_tool_contains tool="edit"
THEN assert_active_tool_contains tool="bash"

[SCENARIO: TOOLCFG-002] TITLE: full 预设包含全部 7 个工具 TAGS: unit tool_config
GIVEN init_tool_config
WHEN get_preset name="full"
THEN assert_preset_contains tool="read"
THEN assert_preset_contains tool="bash"
THEN assert_preset_contains tool="grep"
THEN assert_preset_contains tool="find"
THEN assert_preset_contains tool="ls"
THEN assert_preset_count expected=7

[SCENARIO: TOOLCFG-003] TITLE: readonly 预设不含写操作工具 TAGS: unit tool_config
GIVEN init_tool_config
WHEN get_preset name="readonly"
THEN assert_preset_contains tool="read"
THEN assert_preset_contains tool="grep"
THEN assert_preset_contains tool="find"
THEN assert_preset_contains tool="ls"
THEN assert_preset_not_contains tool="write"
THEN assert_preset_not_contains tool="edit"
THEN assert_preset_not_contains tool="bash"

[SCENARIO: TOOLCFG-004] TITLE: 运行时切换工具集 TAGS: unit tool_config
GIVEN init_tool_config
WHEN set_active_tools tools="read,bash"
THEN assert_active_tool_count expected=2
THEN assert_active_tool_contains tool="read"
THEN assert_active_tool_contains tool="bash"

[SCENARIO: TOOLCFG-005] TITLE: 无效工具名被拒绝 TAGS: unit tool_config
GIVEN init_tool_config
WHEN validate_tools tools="read,nonexistent"
THEN assert_tool_config_error contains="nonexistent"

[SCENARIO: TOOLCFG-006] TITLE: 空列表被拒绝 TAGS: unit tool_config
GIVEN init_tool_config
WHEN set_active_tools_safe tools=""
THEN assert_tool_config_error contains="empty"

# ══════════════════════════════════════════════
# pi-mono bugfix 回归覆盖
# ══════════════════════════════════════════════

[SCENARIO: TOOLCFG-007] TITLE: 工具 schema 默认包含 strict 字段 (Pi#a613306) TAGS: unit tool_config regression
GIVEN init_tool_config
WHEN get_tool_schema tool="bash"
THEN assert_tool_schema_has_field field="strict" expected="false"
