# Agent 集成 BDD 测试
# 对应 architecture.md J.9 节
# 覆盖 Agent 循环、工具调用、错误恢复

# ══════════════════════════════════════════════
# Group 1: Action 管道 (8 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-001] TITLE: 简单文本回复 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="你好，我是 Gong！"
WHEN agent_chat prompt="你好"
THEN assert_agent_reply contains="你好"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-002] TITLE: 单工具调用后回复 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="hello.txt" content="Hello World"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/hello.txt"
GIVEN mock_llm_response response_type="text" content="文件内容是 Hello World"
WHEN agent_chat prompt="读一下 hello.txt"
THEN assert_tool_was_called tool="read_file"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="read_file"
THEN assert_agent_reply contains="Hello World"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-003] TITLE: 多工具链式调用 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="write_file" tool_args="file_path={{workspace}}/out1.txt|content=hello"
GIVEN mock_llm_response response_type="tool_call" tool="write_file" tool_args="file_path={{workspace}}/out2.txt|content=world"
GIVEN mock_llm_response response_type="text" content="执行完毕"
WHEN agent_chat prompt="创建两个文件"
THEN assert_tool_was_called tool="write_file" times=2
THEN assert_file_exists path="out1.txt"
THEN assert_file_content path="out1.txt" expected="hello"
THEN assert_file_exists path="out2.txt"
THEN assert_file_content path="out2.txt" expected="world"

[SCENARIO: BDD-AGENT-004] TITLE: 工具写入文件验证 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="write_file" tool_args="file_path={{workspace}}/output.txt|content=written by gong"
GIVEN mock_llm_response response_type="text" content="文件已写入"
WHEN agent_chat prompt="写一个文件"
THEN assert_agent_reply contains="文件已写入"
THEN assert_file_exists path="output.txt"
THEN assert_file_content path="output.txt" expected="written by gong"

[SCENARIO: BDD-AGENT-005] TITLE: 工具编辑文件 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="code.py" content="print('hello')"
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="edit_file" tool_args="file_path={{workspace}}/code.py|old_string=hello|new_string=world"
GIVEN mock_llm_response response_type="text" content="已修改"
WHEN agent_chat prompt="把 hello 改成 world"
THEN assert_agent_reply contains="已修改"
THEN assert_file_content path="code.py" expected="print('world')"

[SCENARIO: BDD-AGENT-006] TITLE: grep 搜索工具 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="src/main.py" content="def main():\n    print('hello')"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="grep" tool_args="pattern=main|path={{workspace}}"
GIVEN mock_llm_response response_type="text" content="找到 main 函数定义"
WHEN agent_chat prompt="搜索 main"
THEN assert_tool_was_called tool="grep"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="grep"
THEN assert_agent_reply contains="main"

[SCENARIO: BDD-AGENT-007] TITLE: find 文件发现 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="a.py" content="# a"
GIVEN create_temp_file path="b.py" content="# b"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="find_files" tool_args="pattern=*.py|path={{workspace}}"
GIVEN mock_llm_response response_type="text" content="找到 2 个 Python 文件"
WHEN agent_chat prompt="找所有 py 文件"
THEN assert_tool_was_called tool="find_files"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="find_files"
THEN assert_agent_reply contains="Python"

[SCENARIO: BDD-AGENT-008] TITLE: ls 目录列表 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="file1.txt" content="f1"
GIVEN create_temp_file path="file2.txt" content="f2"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="list_directory" tool_args="path={{workspace}}"
GIVEN mock_llm_response response_type="text" content="目录包含 2 个文件"
WHEN agent_chat prompt="列出当前目录"
THEN assert_tool_was_called tool="list_directory"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="list_directory"
THEN assert_agent_reply contains="2"

# ══════════════════════════════════════════════
# Group 2: Anthropic E2E (4 个场景)
# 需要 API key，通过 --exclude e2e 跳过
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-009] TITLE: E2E 简单问答 TAGS: integration e2e agent
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="1+1等于几？请只回答数字"
THEN assert_agent_reply contains="2"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-010] TITLE: E2E 文件读取 TAGS: integration e2e agent
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="E2E test content"
GIVEN configure_agent
WHEN agent_chat prompt="读一下 test.txt 的内容"
THEN assert_agent_reply contains="E2E test content"
THEN assert_tool_was_called tool="read_file"

[SCENARIO: BDD-AGENT-011] TITLE: E2E 文件写入 TAGS: integration e2e agent
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="在当前目录创建 hello.txt，内容写 hello from gong"
THEN assert_file_exists path="hello.txt"
THEN assert_file_content path="hello.txt" expected="hello from gong"
THEN assert_tool_was_called tool="write_file"

[SCENARIO: BDD-AGENT-012] TITLE: E2E 多轮工具调用 TAGS: integration e2e agent
GIVEN create_temp_dir
GIVEN create_temp_file path="data.txt" content="original data"
GIVEN configure_agent
WHEN agent_chat prompt="先读 data.txt，然后把 original 改成 modified"
THEN assert_tool_was_called tool="read_file"
THEN assert_tool_was_called tool="edit_file"
THEN assert_file_content path="data.txt" expected="modified data"

# ══════════════════════════════════════════════
# Group 3: 路由 (1 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-013] TITLE: 信号路由到正确策略 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN attach_telemetry_handler event="gong.agent.end"
GIVEN mock_llm_response response_type="text" content="路由成功"
WHEN agent_chat prompt="测试路由"
THEN assert_agent_reply contains="路由成功"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_telemetry_received event="gong.agent.end"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 4: Pi 回归 (7 个场景)
# 测试之前可能出现的回归问题
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-014] TITLE: 空回复处理 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN attach_telemetry_handler event="gong.agent.end"
GIVEN mock_llm_response response_type="text" content=""
WHEN agent_chat prompt="说点什么"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_telemetry_received event="gong.agent.end"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-015] TITLE: 中文回复 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="这是一段中文回复"
WHEN agent_chat prompt="用中文回复"
THEN assert_agent_reply contains="中文回复"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-016] TITLE: 长文本回复 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="这是一段很长的回复内容包含了很多字符用来模拟长文本返回"
WHEN agent_chat prompt="给一个长回复"
THEN assert_agent_reply contains="长文本返回"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-017] TITLE: 单轮对话生命周期 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN attach_telemetry_handler event="gong.agent.end"
GIVEN attach_telemetry_handler event="gong.turn.start"
GIVEN attach_telemetry_handler event="gong.turn.end"
GIVEN mock_llm_response response_type="text" content="第一轮回复"
WHEN agent_chat prompt="第一轮"
THEN assert_agent_reply contains="第一轮回复"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_telemetry_received event="gong.turn.start"
THEN assert_telemetry_received event="gong.turn.end"
THEN assert_telemetry_received event="gong.agent.end"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-018] TITLE: 工具调用后中文路径 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="data/test.txt" content="中文路径测试内容"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/data/test.txt"
GIVEN mock_llm_response response_type="text" content="读到了中文路径文件内容"
WHEN agent_chat prompt="读 data/test.txt"
THEN assert_tool_was_called tool="read_file"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="read_file"
THEN assert_agent_reply contains="中文路径"

[SCENARIO: BDD-AGENT-019] TITLE: 不存在工具的处理 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="nonexistent_tool" tool_args=""
GIVEN mock_llm_response response_type="text" content="工具不存在换个方式"
WHEN agent_chat prompt="做些什么"
THEN assert_tool_was_called tool="nonexistent_tool"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="nonexistent_tool"
THEN assert_agent_reply contains="换个方式"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-020] TITLE: bash 工具调用 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo ok > {{workspace}}/bash_out.txt"
GIVEN mock_llm_response response_type="text" content="命令执行成功"
WHEN agent_chat prompt="执行命令"
THEN assert_tool_was_called tool="bash"
THEN assert_file_exists path="bash_out.txt"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 5: 错误恢复 (6 个场景)
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-021] TITLE: LLM 返回错误后恢复 TAGS: integration agent negative
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN mock_llm_response response_type="error" content="API rate limit exceeded"
WHEN agent_chat prompt="你好"
THEN assert_last_error error_contains="rate limit"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-022] TITLE: 工具执行失败后继续 TAGS: integration agent negative
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path=/nonexistent/file.txt"
GIVEN mock_llm_response response_type="text" content="文件不存在让我换个方式"
WHEN agent_chat prompt="读一个不存在的文件"
THEN assert_tool_was_called tool="read_file"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="read_file"
THEN assert_agent_reply contains="不存在"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-023] TITLE: bash 命令超时后继续 TAGS: integration agent negative
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.tool.start"
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=tail -f /dev/null|timeout=1"
GIVEN mock_llm_response response_type="text" content="命令超时了"
WHEN agent_chat prompt="执行一个会超时的命令"
THEN assert_tool_was_called tool="bash"
THEN assert_telemetry_received event="gong.tool.start" metadata_contains="bash"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="bash"
THEN assert_agent_reply contains="超时"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-024] TITLE: 权限拒绝后继续 TAGS: integration agent negative
GIVEN create_temp_dir
GIVEN create_temp_file path="readonly.txt" content="protected"
GIVEN set_file_permission path="readonly.txt" mode="444"
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="write_file" tool_args="file_path={{workspace}}/readonly.txt|content=overwrite"
GIVEN mock_llm_response response_type="text" content="写入被拒绝了"
WHEN agent_chat prompt="覆写只读文件"
THEN assert_tool_was_called tool="write_file"
THEN assert_file_content path="readonly.txt" expected="protected"
THEN assert_agent_reply contains="拒绝"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-025] TITLE: 连续错误不崩溃 TAGS: integration agent negative
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path=/no/such/file1"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path=/no/such/file2"
GIVEN mock_llm_response response_type="text" content="两次都失败了"
WHEN agent_chat prompt="读两个不存在的文件"
THEN assert_tool_was_called tool="read_file" times=2
THEN assert_agent_reply contains="失败"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-026] TITLE: Agent 进程存活性 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="第一次成功"
WHEN agent_chat prompt="第一次对话"
THEN assert_agent_reply contains="第一次成功"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 6: 流式输出（2 个场景）
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-027] TITLE: 流式输出事件序列 TAGS: integration agent
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="流式测试"
WHEN agent_stream prompt="测试流式"
THEN assert_stream_events sequence="start,delta,end"
THEN assert_agent_reply contains="流式测试"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-028] TITLE: 流式输出含工具调用 TAGS: integration agent
GIVEN create_temp_dir
GIVEN create_temp_file path="stream.txt" content="流式内容"
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/stream.txt"
GIVEN mock_llm_response response_type="text" content="流式工具完成"
WHEN agent_stream prompt="流式读文件"
THEN assert_tool_was_called tool="read_file"
THEN assert_agent_reply contains="流式工具完成"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 7: Hook 端到端集成（2 个场景）
# ══════════════════════════════════════════════

[SCENARIO: BDD-AGENT-029] TITLE: Hook 拦截工具后 Agent 继续对话 TAGS: integration agent hook
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="BlockBash"
GIVEN mock_llm_response response_type="tool_call" tool="bash" tool_args="command=echo hack"
GIVEN mock_llm_response response_type="text" content="工具被拦截了"
WHEN agent_chat prompt="执行命令"
THEN assert_agent_reply contains="工具被拦截了"
THEN assert_no_crash

[SCENARIO: BDD-AGENT-030] TITLE: Hook 变换结果后 Agent 获取变换后内容 TAGS: integration agent hook
GIVEN create_temp_dir
GIVEN create_temp_file path="key.txt" content="api_key=sk_test_AbCdEfGhIjKlMnOpQrStUvWxYz123456"
GIVEN configure_agent
GIVEN register_hook module="RedactApiKey"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/key.txt"
GIVEN mock_llm_response response_type="text" content="密钥已脱敏"
WHEN agent_chat prompt="读取密钥"
THEN assert_tool_was_called tool="read_file"
THEN assert_agent_reply contains="密钥已脱敏"
THEN assert_no_crash
