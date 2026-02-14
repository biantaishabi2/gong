# Prompt 工程 BDD 测试
# 覆盖 prompt.ex 的系统提示构建、格式化、摘要提示

# ══════════════════════════════════════════════
# Group 1: 系统提示构建（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROMPT-001] TITLE: 默认系统提示包含关键指令 TAGS: unit prompt
GIVEN create_temp_dir
WHEN build_default_prompt
THEN assert_prompt_text contains="Gong"
THEN assert_prompt_text contains="工具"

[SCENARIO: PROMPT-002] TITLE: 带工作目录的系统提示 TAGS: unit prompt
GIVEN create_temp_dir
WHEN build_workspace_prompt
THEN assert_prompt_text contains="工作目录"

[SCENARIO: PROMPT-003] TITLE: 对话格式化截断超长内容 TAGS: unit prompt
GIVEN create_temp_dir
GIVEN prompt_messages_with_long_content length=2000
WHEN format_conversation
THEN assert_formatted_length max=600

# ══════════════════════════════════════════════
# Group 2: 摘要提示逻辑（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROMPT-004] TITLE: 无文件操作时显示提示文本 TAGS: unit prompt
GIVEN prompt_messages_plain count=3
WHEN extract_prompt_file_ops
THEN assert_file_ops_text contains="无文件操作"

[SCENARIO: PROMPT-005] TITLE: 多工具调用提取全部文件操作 TAGS: unit prompt
GIVEN prompt_messages_multi_tools tools="read_file:/a.txt,write_file:/b.txt,edit_file:/c.txt"
WHEN extract_prompt_file_ops
THEN assert_file_ops_text contains="read_file"
THEN assert_file_ops_text contains="write_file"
THEN assert_file_ops_text contains="edit_file"

[SCENARIO: PROMPT-006] TITLE: find_previous_summary 定位前次摘要 TAGS: unit prompt
GIVEN prompt_messages_with_summary summary="Goal: 重构代码"
WHEN find_previous_summary
THEN assert_previous_summary contains="重构代码"

[SCENARIO: PROMPT-007] TITLE: 无前次摘要返回 nil TAGS: unit prompt
GIVEN prompt_messages_plain count=3
WHEN find_previous_summary
THEN assert_previous_summary_nil
