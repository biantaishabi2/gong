# Prompt 模板系统 BDD 测试
# 覆盖模板注册、获取、渲染

# ══════════════════════════════════════════════
# Group 1: Prompt 模板管理（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: TEMPLATE-001] TITLE: 内置模板可获取 TAGS: unit template
GIVEN create_temp_dir
WHEN init_prompt_templates
WHEN get_template name="code_review"
THEN assert_template_exists name="code_review"

[SCENARIO: TEMPLATE-002] TITLE: 注册自定义模板 TAGS: unit template
GIVEN create_temp_dir
WHEN init_prompt_templates
WHEN register_template name="my_template" content="请{{action}}以下内容：\n{{content}}"
WHEN get_template name="my_template"
THEN assert_template_exists name="my_template"
THEN assert_template_variables expected="action,content"

[SCENARIO: TEMPLATE-003] TITLE: 渲染模板替换变量 TAGS: unit template
GIVEN create_temp_dir
WHEN init_prompt_templates
WHEN render_template name="code_review" bindings="code:hello world"
THEN assert_rendered_content contains="hello world"

[SCENARIO: TEMPLATE-004] TITLE: 获取不存在的模板 TAGS: unit template
GIVEN create_temp_dir
WHEN init_prompt_templates
WHEN get_template_expect_error name="nonexistent"
THEN assert_template_error contains="not_found"
