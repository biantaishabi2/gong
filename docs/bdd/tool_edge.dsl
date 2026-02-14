# 工具调用边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的工具调用异常处理

# ══════════════════════════════════════════════
# Group 1: 参数边界（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: TOOL-EDGE-001] TITLE: 工具参数为 nil/空 map 时返回合理错误 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_dispatch_nil_params tool_name="read_file"
THEN assert_tool_error error_contains="参数"

[SCENARIO: TOOL-EDGE-005] TITLE: 工具错误返回 ToolResult(is_error: true) TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_read path="/nonexistent_file_xyz.txt"
THEN assert_tool_error error_contains="ENOENT"

# ══════════════════════════════════════════════
# Group 2: 工具名与 ID 边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: TOOL-EDGE-002] TITLE: 工具名大小写不敏感匹配 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="case_test.txt" content="case insensitive"
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="tool_call" tool="Read_File" tool_args="file_path={{workspace}}/case_test.txt"
GIVEN mock_llm_response response_type="text" content="读取成功"
WHEN agent_chat prompt="读文件"
THEN assert_agent_reply contains="读取成功"
THEN assert_no_crash

[SCENARIO: TOOL-EDGE-003] TITLE: 工具调用 ID 含特殊字符正常处理 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="id_test.txt" content="special id"
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/id_test.txt" tool_id="call:id/with-special_chars.123"
GIVEN mock_llm_response response_type="text" content="id正常"
WHEN agent_chat prompt="test"
THEN assert_agent_reply contains="id正常"
THEN assert_no_crash

[SCENARIO: TOOL-EDGE-004] TITLE: 孤儿 tool_result 不导致循环崩溃 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN mock_orphan_tool_result
GIVEN mock_llm_response response_type="text" content="已恢复"
WHEN agent_chat_with_orphan prompt="handle orphan"
THEN assert_no_loop_crash
THEN assert_agent_reply contains="已恢复"

# ══════════════════════════════════════════════
# Group 3: 错误消息与响应边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: TOOL-EDGE-006] TITLE: 错误消息包含可操作提示 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="tool_call" tool="nonexistent_tool_xyz" tool_args="param=value"
GIVEN mock_llm_response response_type="text" content="工具不存在"
WHEN agent_chat prompt="use tool"
THEN assert_tool_error_has_available_tools

[SCENARIO: TOOL-EDGE-007] TITLE: 空 content assistant 消息被过滤 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="text" content=""
GIVEN mock_llm_response response_type="text" content="真正回复"
WHEN agent_chat prompt="say nothing"
THEN assert_empty_content_filtered
