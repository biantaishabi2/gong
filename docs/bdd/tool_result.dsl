# 工具结果双通道 BDD 场景
# 覆盖 Gong.ToolResult 的构造、兼容、双通道分离

[SCENARIO: TOOLRES-001] TITLE: from_text 兼容旧格式 TAGS: unit tool_result
WHEN tool_result_from_text text="File written successfully"
THEN assert_tool_result_content contains="File written successfully"
THEN assert_tool_result_details_nil

[SCENARIO: TOOLRES-002] TITLE: new 构造带 details TAGS: unit tool_result
WHEN tool_result_new content="Edited: /src/main.ex" details_key="diff_lines" details_value="3"
THEN assert_tool_result_content contains="Edited"
THEN assert_tool_result_has_details key="diff_lines"

[SCENARIO: TOOLRES-003] TITLE: 错误结果标记 TAGS: unit tool_result
WHEN tool_result_error content="File not found: /tmp/nope"
THEN assert_tool_result_is_error
THEN assert_tool_result_content contains="not found"

[SCENARIO: TOOLRES-004] TITLE: content 和 details 独立 TAGS: unit tool_result
WHEN tool_result_new content="OK" details_key="exit_code" details_value="0"
THEN assert_tool_result_content contains="OK"
THEN assert_tool_result_has_details key="exit_code"
THEN assert_tool_result_details_value key="exit_code" expected="0"

[SCENARIO: TOOLRES-005] TITLE: details 为 nil 时不影响 content TAGS: unit tool_result
WHEN tool_result_from_text text="hello world"
THEN assert_tool_result_content contains="hello"
THEN assert_tool_result_details_nil

[SCENARIO: TOOLRES-006] TITLE: is_error 默认为 false TAGS: unit tool_result
WHEN tool_result_from_text text="success"
THEN assert_tool_result_not_error

# ── 集成场景：工具实际返回 ToolResult ──

[SCENARIO: TOOLRES-101] TITLE: edit 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
GIVEN create_temp_file path="target.txt" content="hello world"
WHEN tool_edit path="target.txt" old_string="hello" new_string="hi"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="target.txt"
THEN assert_result_field field="replacements" expected="1"

[SCENARIO: TOOLRES-102] TITLE: bash 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
WHEN tool_bash command="echo dual_channel_test"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="dual_channel_test"
THEN assert_exit_code expected=0

[SCENARIO: TOOLRES-103] TITLE: read 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
GIVEN create_temp_file path="sample.txt" content="line1\nline2\nline3"
WHEN tool_read path="sample.txt"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="line1" truncated=false

[SCENARIO: TOOLRES-104] TITLE: write 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
WHEN tool_write path="out.txt" content="written"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="out.txt"
THEN assert_result_field field="bytes_written" expected="7"

[SCENARIO: TOOLRES-105] TITLE: grep 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
GIVEN create_temp_file path="grep_target.txt" content="alpha\nbeta\ngamma"
WHEN tool_grep pattern="beta" path="grep_target.txt"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="beta"

[SCENARIO: TOOLRES-106] TITLE: find 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
GIVEN create_temp_file path="findme.txt" content="x"
WHEN tool_find pattern="findme.txt"
THEN assert_is_tool_result
THEN assert_tool_success content_contains="findme.txt"

[SCENARIO: TOOLRES-107] TITLE: ls 返回双通道 ToolResult TAGS: external_io integration tool_result
GIVEN create_temp_dir
GIVEN create_temp_file path="visible.txt" content="y"
WHEN tool_ls path="."
THEN assert_is_tool_result
THEN assert_tool_success content_contains="visible.txt"
