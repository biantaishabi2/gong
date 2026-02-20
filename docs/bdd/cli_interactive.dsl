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

[SCENARIO: CLI-CMD-007] TITLE: run --model 参数解析 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="run --model openai:gpt-4 hello"
THEN assert_cli_command expected="run"
THEN assert_cli_opt key="model" expected="openai:gpt-4"
THEN assert_cli_prompt expected="hello"

[SCENARIO: CLI-CMD-008] TITLE: run 无 prompt 解析为空字符串 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_parse argv="run"
THEN assert_cli_command expected="run"
THEN assert_cli_prompt expected=""

# ══════════════════════════════════════════════
# Group 2: Renderer 事件格式化 — Step2 (5+4 场景)
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

[SCENARIO: CLI-RENDER-006] TITLE: message.start 渲染为 noop TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="message.start"
THEN assert_io_output_empty

[SCENARIO: CLI-RENDER-007] TITLE: error.runtime 也输出到 stderr TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="error.runtime" message="模型不存在"
THEN assert_stderr_output contains="模型不存在"

[SCENARIO: CLI-RENDER-008] TITLE: 连续多事件拼接渲染 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="message.delta" content="你好"
WHEN render_event type="message.delta" content="世界"
WHEN render_event type="message.end"
THEN assert_io_output contains="你好世界"

[SCENARIO: CLI-RENDER-009] TITLE: tool.start 参数超长截断 TAGS: unit cli renderer
GIVEN create_temp_dir
GIVEN capture_io
WHEN render_event type="tool.start" tool_name="bash" tool_args="command=echo_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
THEN assert_io_output contains="bash"
THEN assert_io_output contains="..."

# ══════════════════════════════════════════════
# Group 3: Run 单次执行 — Step2 (3+1 场景)
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

[SCENARIO: CLI-RUN-004] TITLE: run 空 prompt 返回 usage 错误 TAGS: unit cli
GIVEN create_temp_dir
WHEN cli_run argv="run"
THEN assert_cli_exit_code expected=2

# ══════════════════════════════════════════════
# Group 4: Chat REPL 斜杠命令 — Step2 (4+3 场景)
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
GIVEN mock_llm_response response_type="text" content="历史测试回复"
GIVEN start_chat_session
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

[SCENARIO: CLI-CHAT-005] TITLE: /clear 提示对话已清空 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN start_chat_session
GIVEN capture_io
WHEN chat_input text="/clear"
THEN assert_io_output contains="清空"

[SCENARIO: CLI-CHAT-006] TITLE: 普通对话发送并收到回复 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="你好啊朋友"
GIVEN start_chat_session
WHEN chat_input text="你好"
WHEN chat_wait_completion
GIVEN capture_io
WHEN chat_input text="/history"
THEN assert_io_output contains="你好"
THEN assert_io_output contains="你好啊朋友"

[SCENARIO: CLI-CHAT-007] TITLE: 多轮对话历史累积 TAGS: integration cli chat
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN mock_llm_response response_type="text" content="回复一"
GIVEN mock_llm_response response_type="text" content="回复二"
GIVEN start_chat_session
WHEN chat_input text="问题一"
WHEN chat_wait_completion
WHEN chat_input text="问题二"
WHEN chat_wait_completion
GIVEN capture_io
WHEN chat_input text="/history"
THEN assert_io_output contains="问题一"
THEN assert_io_output contains="问题二"

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

[SCENARIO: CLI-SESSION-005] TITLE: 多会话 list 排序 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="问题A"
GIVEN tape_append kind="assistant" content="回复A"
GIVEN tape_save_session session_id="multi-001"
GIVEN tape_append kind="user" content="问题B"
GIVEN tape_append kind="assistant" content="回复B"
GIVEN tape_save_session session_id="multi-002"
WHEN cli_session_list
THEN assert_session_list_count expected=2
THEN assert_session_list_contains session_id="multi-001"
THEN assert_session_list_contains session_id="multi-002"

[SCENARIO: CLI-SESSION-006] TITLE: 覆盖保存同一 session_id TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="旧内容"
GIVEN tape_save_session session_id="dup-001"
GIVEN tape_append kind="user" content="新内容"
GIVEN tape_append kind="assistant" content="新回复"
GIVEN tape_save_session session_id="dup-001"
WHEN cli_session_list
THEN assert_session_list_count expected=1
WHEN cli_session_restore session_id="dup-001"
THEN assert_session_restored
THEN assert_session_history_contains content="新内容"

[SCENARIO: CLI-SESSION-007] TITLE: restore 验证 user + assistant 双角色 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="用户提问"
GIVEN tape_append kind="assistant" content="助手回复"
GIVEN tape_save_session session_id="dual-role-001"
WHEN cli_session_restore session_id="dual-role-001"
THEN assert_session_restored
THEN assert_session_history_contains content="用户提问"
THEN assert_session_history_contains content="助手回复"

[SCENARIO: CLI-SESSION-008] TITLE: 损坏 JSON 文件容错 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="正常会话"
GIVEN tape_append kind="assistant" content="正常回复"
GIVEN tape_save_session session_id="good-session"
GIVEN create_corrupt_session_file filename="bad-session.json"
WHEN cli_session_list
THEN assert_session_list_count expected=1
THEN assert_session_list_contains session_id="good-session"

[SCENARIO: CLI-SESSION-009] TITLE: save → restore 往返一致性 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="往返问题"
GIVEN tape_append kind="assistant" content="往返回复"
GIVEN tape_save_session session_id="roundtrip-001"
WHEN cli_session_restore session_id="roundtrip-001"
THEN assert_session_restored
THEN assert_session_history_contains content="往返问题"
THEN assert_session_history_contains content="往返回复"

[SCENARIO: CLI-SESSION-010] TITLE: 多轮对话 history TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="第一轮问题"
GIVEN tape_append kind="assistant" content="第一轮回复"
GIVEN tape_append kind="user" content="第二轮问题"
GIVEN tape_append kind="assistant" content="第二轮回复"
GIVEN tape_append kind="user" content="第三轮问题"
GIVEN tape_append kind="assistant" content="第三轮回复"
GIVEN tape_save_session session_id="multi-turn-001"
WHEN cli_session_restore session_id="multi-turn-001"
THEN assert_session_restored
THEN assert_session_history_contains content="第一轮问题"
THEN assert_session_history_contains content="第一轮回复"
THEN assert_session_history_contains content="第二轮问题"
THEN assert_session_history_contains content="第二轮回复"
THEN assert_session_history_contains content="第三轮问题"
THEN assert_session_history_contains content="第三轮回复"

# ══════════════════════════════════════════════
# Group 6: 长对话压缩 CLI 集成 — Step4 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: CLI-COMPACT-001] TITLE: chat 长对话自动触发压缩 TAGS: integration cli compaction
GIVEN create_temp_dir
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="这是一段很长的回复用于触发压缩检测当上下文令牌数超过预设预算时系统应自动执行压缩操作以确保对话历史不会无限膨胀导致内存溢出和性能下降同时保留关键上下文信息让后续对话能够正常继续"
WHEN chat_input text="生成长回复"
WHEN chat_wait_completion
THEN assert_compaction_triggered
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-002] TITLE: 压缩后 chat 继续正常对话 TAGS: integration cli compaction
GIVEN create_temp_dir
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="超长回复触发压缩后的第一轮内容用于填充上下文窗口确保令牌数超过预设阈值从而自动触发压缩流程验证压缩后系统仍然能够正常处理后续对话请求不会丢失关键信息"
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
GIVEN mock_llm_response response_type="text" content="压缩前的长回复内容用于填充上下文窗口使得令牌总量超过压缩阈值从而在下一轮对话之前自动触发压缩操作随后通过保存命令验证压缩后的会话状态能够正确持久化到磁盘"
WHEN chat_input text="触发压缩"
WHEN chat_wait_completion
WHEN chat_input text="/save"
THEN assert_session_saved
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-004] TITLE: 压缩后 save → restore 往返验证历史 TAGS: integration cli compaction session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="这段超长回复用于触发自动压缩机制当上下文令牌总量超过配置的窗口大小减去保留量的阈值时系统会自动执行压缩将旧消息替换为摘要以控制上下文长度"
WHEN chat_input text="请生成长回复触发压缩"
WHEN chat_wait_completion
THEN assert_compaction_triggered
WHEN chat_input text="/save"
THEN assert_session_saved
WHEN cli_session_restore
THEN assert_session_restored
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-005] TITLE: restore 压缩会话后继续对话 TAGS: integration cli compaction session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="第一轮超长回复用于填充上下文窗口触发自动压缩流程确保令牌数量超过预设阈值以便验证压缩后保存再恢复的完整链路同时还需要足够长度确保令牌估算超过上下文窗口减去保留量的压缩触发阈值"
GIVEN mock_llm_response response_type="text" content="恢复后的新回复"
WHEN chat_input text="第一轮触发压缩"
WHEN chat_wait_completion
THEN assert_compaction_triggered
WHEN chat_input text="/save"
THEN assert_session_saved
WHEN chat_session_restore
WHEN chat_input text="恢复后继续"
WHEN chat_wait_completion
THEN assert_agent_reply contains="恢复后的新回复"
THEN assert_no_crash

[SCENARIO: CLI-COMPACT-006] TITLE: 短对话不触发压缩 TAGS: integration cli compaction
GIVEN create_temp_dir
GIVEN configure_agent context_window=200 reserve_tokens=50
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="短回复"
WHEN chat_input text="你好"
WHEN chat_wait_completion
THEN assert_compaction_not_triggered
THEN assert_no_crash

[SCENARIO: CLI-SESSION-011] TITLE: 关闭会话自动持久化并可恢复 TAGS: integration cli session
GIVEN create_temp_dir
GIVEN tape_init
GIVEN start_chat_session
GIVEN mock_llm_response response_type="text" content="自动保存测试回复"
WHEN chat_input text="测试消息"
WHEN chat_wait_completion
WHEN chat_input text="/exit"
THEN assert_session_saved
WHEN cli_session_restore
THEN assert_session_restored
THEN assert_session_history_contains content="测试消息"
