# Resource 发现 BDD 测试
# 覆盖 .gong/context/ 下资源文件的发现和加载

# ══════════════════════════════════════════════
# Group 1: Resource 发现 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: RESOURCE-001] TITLE: 发现 context 下 md 文件并注入 TAGS: unit resource
GIVEN create_temp_dir
GIVEN create_resource_dir scope="project"
GIVEN create_resource_file name="rules.md" content="# Project Rules\nAlways use TypeScript"
WHEN load_resources
THEN assert_resource_count expected=1
THEN assert_resource_content contains="TypeScript"

[SCENARIO: RESOURCE-002] TITLE: 全局加项目两级合并项目优先 TAGS: unit resource
GIVEN create_temp_dir
GIVEN create_resource_dir scope="project"
GIVEN create_resource_file name="style.md" content="# Style Guide\nUse 2 spaces"
GIVEN create_resource_file name="api.md" content="# API Rules\nREST only"
WHEN load_resources
THEN assert_resource_count expected=2

[SCENARIO: RESOURCE-003] TITLE: reload 后新内容生效 TAGS: unit resource
GIVEN create_temp_dir
GIVEN create_resource_dir scope="project"
GIVEN create_resource_file name="rules.md" content="# Version 1"
WHEN load_resources
THEN assert_resource_content contains="Version 1"
GIVEN create_resource_file name="rules.md" content="# Version 2"
WHEN reload_resources
THEN assert_resource_content contains="Version 2"
