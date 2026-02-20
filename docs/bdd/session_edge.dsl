# 会话/存储边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的会话 fork 和消息顺序问题

# ══════════════════════════════════════════════
# Group 1: 会话 fork 与恢复（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: SESSION-ERR-001] TITLE: fork 后父会话内容不变 TAGS: unit tape smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="msg1"
GIVEN tape_append kind="assistant" content="reply1"
GIVEN tape_fork
THEN assert_entry_count expected=2

[SCENARIO: SESSION-ERR-002] TITLE: fork 后子会话保留用户消息 TAGS: unit tape smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="original"
GIVEN tape_fork
GIVEN tape_append kind="user" content="forked_msg"
THEN assert_entry_count expected=2

[SCENARIO: SESSION-ERR-003] TITLE: 恢复会话时消息顺序正确 TAGS: unit tape smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="first"
GIVEN tape_append kind="assistant" content="second"
GIVEN tape_append kind="user" content="third"
WHEN when_tape_init
THEN assert_entry_count expected=3
THEN assert_entry_order sequence="first,second,third"

[SCENARIO: SESSION-ERR-004] TITLE: 错误/中止消息在会话树中可见 TAGS: unit tape smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="error" content="something went wrong"
THEN assert_entry_count expected=1
THEN assert_entry_order sequence="something went wrong"

# ══════════════════════════════════════════════
# Group 2: Fork/Merge 和恢复（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: SESSION-ERR-005] TITLE: 待处理消息在 session 切换时被清理 TAGS: unit tape smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_add_pending content="pending message 1"
GIVEN tape_add_pending content="pending message 2"
WHEN tape_switch_session
THEN assert_pending_cleared

[SCENARIO: SESSION-ERR-006] TITLE: 异步事件 handler 错误被正确传播 TAGS: unit tape full
GIVEN create_temp_dir
GIVEN register_failing_event_handler
WHEN emit_event event="test_event"
THEN assert_handler_error_propagated

# ══════════════════════════════════════════════
# Group 3: pi-mono bugfix 回归（1 场景）
# ══════════════════════════════════════════════

[SCENARIO: SESSION-ERR-007] TITLE: 最后 assistant 查找跳过 aborted 空消息 (Pi#e30c4e3) TAGS: unit tape regression smoke
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="问题"
GIVEN tape_append kind="assistant" content="有内容的回复"
GIVEN tape_append kind="assistant" content="" metadata_kv="stop_reason:aborted"
WHEN when_tape_get_last_assistant
THEN assert_tape_last_content contains="有内容的回复"

# ══════════════════════════════════════════════
# Group 4: pi-mono bugfix 回归覆盖（4 场景）
# ══════════════════════════════════════════════

# 说明：该场景在 flush 重置断言之外，补充 tape store 条目状态断言，避免仅靠描述性校验。
[SCENARIO: SESSION-ERR-008] TITLE: 分叉后仅 user 消息的 flush 重置（增强语义校验） (Pi#b5be54b) TAGS: unit tape regression full
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="原始消息"
GIVEN tape_fork
GIVEN tape_append kind="user" content="分叉后用户消息"
WHEN when_tape_flush
THEN assert_flush_reset
THEN assert_entry_count expected=2

[SCENARIO: SESSION-RETRY-001] TITLE: fetch failed 错误可重试回归 TAGS: integration agent retry regression smoke
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.retry"
GIVEN mock_llm_response response_type="error" content="fetch failed"
GIVEN mock_llm_response response_type="text" content="fetch failed 重试后恢复"
WHEN agent_chat prompt="触发 fetch failed 重试"
THEN assert_retry_happened
THEN assert_agent_reply contains="重试后恢复"
THEN assert_no_crash

[SCENARIO: SESSION-RETRY-002] TITLE: connection error 错误可重试回归 TAGS: integration agent retry regression smoke
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.retry"
GIVEN mock_llm_response response_type="error" content="connection error"
GIVEN mock_llm_response response_type="text" content="connection error 重试后恢复"
WHEN agent_chat prompt="触发 connection error 重试"
THEN assert_retry_happened
THEN assert_agent_reply contains="重试后恢复"
THEN assert_no_crash

[SCENARIO: SESSION-RETRY-003] TITLE: terminated 错误可重试回归 TAGS: integration agent retry regression smoke
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.retry"
GIVEN mock_llm_response response_type="error" content="connection terminated"
GIVEN mock_llm_response response_type="text" content="terminated 重试后恢复"
WHEN agent_chat prompt="触发 terminated 重试"
THEN assert_retry_happened
THEN assert_agent_reply contains="重试后恢复"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 5: Session→Agent backend 打通 — Step1 新增 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: SESSION-BACKEND-001] TITLE: resolve_backend 接受 :backend 闭包 TAGS: unit session
GIVEN create_temp_dir
GIVEN init_session with_mock_backend="true"
WHEN session_prompt message="backend 闭包测试"
THEN assert_session_reply contains="mock"
THEN assert_no_crash

[SCENARIO: SESSION-BACKEND-002] TITLE: resolve_backend 接受 :model 字符串 TAGS: unit session
GIVEN create_temp_dir
GIVEN init_model_registry
GIVEN register_model name="test_model" provider="deepseek" model_id="deepseek-chat" api_key_env="DEEPSEEK_API_KEY"
GIVEN init_session with_model="deepseek:deepseek-chat"
THEN assert_session_backend_resolved

[SCENARIO: SESSION-BACKEND-003] TITLE: resolve_backend 无效 model 格式返回错误 TAGS: unit session
GIVEN create_temp_dir
GIVEN init_model_registry
WHEN init_session_expect_error with_model="invalid-no-colon"
THEN assert_session_error error_contains="unknown_provider"
