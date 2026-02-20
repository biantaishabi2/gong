# CLI 交互层 BDD 测试
# 覆盖 Step2-4: chat/run/session 命令、Renderer、长对话优化

# ══════════════════════════════════════════════
# Group 1: CLI 命令解析 — Step2 (6 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-CMD-001] TITLE: chat 命令解析 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="chat"
THEN assert_cli_command expected="chat"

[SCENARIO: CLI-CMD-002] TITLE: chat --model 参数解析 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="chat --model deepseek:deepseek-chat"
THEN assert_cli_command expected="chat"
THEN assert_cli_opt key="model" expected="deepseek:deepseek-chat"

[SCENARIO: CLI-CMD-003] TITLE: run 命令解析含 prompt TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="run hello world"
THEN assert_cli_command expected="run"
THEN assert_cli_prompt expected="hello world"

[SCENARIO: CLI-CMD-004] TITLE: session list 命令解析 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="session list"
THEN assert_cli_command expected="session_list"

[SCENARIO: CLI-CMD-005] TITLE: session restore 命令解析 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="session restore abc123"
THEN assert_cli_command expected="session_restore"
THEN assert_cli_session_id expected="abc123"

[SCENARIO: CLI-CMD-006] TITLE: 未知命令返回 usage 错误 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_run argv="unknown_cmd"
THEN assert_cli_exit_code expected=2

# ══════════════════════════════════════════════
# Group 2: Renderer 事件格式化 — Step2 (5 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-RENDER-001] TITLE: text_delta 渲染为文本追加 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="message.delta" content="你好世界"
THEN assert_io_output contains="你好世界"

[SCENARIO: CLI-RENDER-002] TITLE: message.end 渲染换行 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="message.end"
THEN assert_io_output contains="\n"

[SCENARIO: CLI-RENDER-003] TITLE: tool.start 渲染工具名 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="tool.start" tool_name="read_file" tool_args="{\"file_path\":\"/tmp/a.txt\"}"
THEN assert_io_output contains="read_file"

[SCENARIO: CLI-RENDER-004] TITLE: tool.end 渲染截断结果 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="tool.end" tool_name="read_file" result="文件内容很长很长的一段文字用来测试截断"
THEN assert_io_output_max_length max=250

[SCENARIO: CLI-RENDER-005] TITLE: error 事件渲染到 stderr TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="error.stream" message="连接超时"
THEN assert_stderr_output contains="连接超时"

# ══════════════════════════════════════════════
# Group 3: Run 单次执行 — Step2 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-RUN-001] TITLE: run 命令单次执行返回文本 TAGS: integration cli
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="单次执行结果"
WHEN cli_run_prompt prompt="测试 run"
THEN assert_cli_output contains="单次执行结果"
THEN assert_cli_exit_code expected=0

[SCENARIO: CLI-RUN-002] TITLE: run 命令执行失败返回 exit code 1 TAGS: integration cli
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="error" content="permanent auth failure"
WHEN cli_run_prompt prompt="触发错误"
THEN assert_cli_exit_code expected=1

[SCENARIO: CLI-RUN-003] TITLE: run 命令带工具调用 TAGS: integration cli
GIVEN create_temp_dir
GIVEN create_temp_file path="run_test.txt" content="run mode data"
GIVEN configure_agent
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/run_test.txt"
GIVEN mock_llm_response response_type="text" content="文件内容是 run mode data"
WHEN cli_run_prompt prompt="读取 run_test.txt"
THEN assert_cli_output contains="run mode data"
THEN assert_cli_exit_code expected=0

# ══════════════════════════════════════════════
# Group 4: Chat REPL 斜杠命令 — Step2 (4 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-CHAT-001] TITLE: /exit 关闭会话 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN start_chat_session
WHEN chat_input text="/exit"
THEN assert_session_closed

[SCENARIO: CLI-CHAT-002] TITLE: /help 显示帮助 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN start_chat_session
GIVEN capture_io
WHEN chat_input text="/help"
THEN assert_io_output contains="/exit"
THEN assert_io_output contains="/history"

[SCENARIO: CLI-CHAT-003] TITLE: /history 显示对话历史 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="历史测试回复"
WHEN chat_input text="你好"
WHEN chat_wait_completion
GIVEN capture_io
WHEN chat_input text="/history"
THEN assert_io_output contains="你好"

[SCENARIO: CLI-CHAT-004] TITLE: 空输入不触发 Agent TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN start_chat_session
WHEN chat_input text=""
THEN assert_no_agent_call

# ══════════════════════════════════════════════
# Group 5: Session list/restore — Step3 (4 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-SESSION-001] TITLE: session list 空列表 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
WHEN cli_session_list
THEN assert_session_list_count expected=0

[SCENARIO: CLI-SESSION-002] TITLE: session list 有已保存会话 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="测试消息"
GIVEN tape_append kind="assistant" content="测试回复"
GIVEN tape_save_session session_id="test-session-001"
WHEN cli_session_list
THEN assert_session_list_count expected=1
THEN assert_session_list_contains session_id="test-session-001"

[SCENARIO: CLI-SESSION-003] TITLE: session restore 恢复历史 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="历史问题"
GIVEN tape_append kind="assistant" content="历史回复"
GIVEN tape_save_session session_id="restore-001"
WHEN cli_session_restore session_id="restore-001"
THEN assert_session_restored
THEN assert_session_history_contains content="历史问题"

[SCENARIO: CLI-SESSION-004] TITLE: session restore 不存在的 ID 返回错误 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
WHEN cli_session_restore session_id="nonexistent-id"
THEN assert_session_restore_error error_contains="not_found"

# ══════════════════════════════════════════════
# Group 6: 长对话压缩 CLI 集成 — Step4 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-COMPACT-001] TITLE: chat 长对话自动触发压缩 TAGS: integration cli compaction
GIVEN create_temp_dir
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="这是一段很长的回复用于触发压缩检测当上下文令牌数超过预设预算时系统应自动执行压缩"
WHEN chat_input text="生成长回复"
WHEN chat_wait_completion
THEN assert_compaction_triggered
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-002] TITLE: 压缩后 chat 继续正常对话 TAGS: integration cli compaction
GIVEN create_temp_dir
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="超长回复触发压缩后的第一轮内容用于填充上下文窗口"
GIVEN mock_llm_response response_type="text" content="压缩后继续正常"
WHEN chat_input text="第一轮"
WHEN chat_wait_completion
WHEN chat_input text="第二轮"
WHEN chat_wait_completion
THEN assert_agent_reply contains="压缩后继续正常"
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-003] TITLE: /save 保存压缩后的会话 TAGS: integration cli compaction session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="压缩前的长回复内容用于填充上下文"
WHEN chat_input text="触发压缩"
WHEN chat_wait_completion
WHEN chat_input text="/save"
THEN assert_session_saved
THEN assert_no_crash
