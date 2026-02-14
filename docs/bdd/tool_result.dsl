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
