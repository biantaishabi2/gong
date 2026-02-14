# 会话/存储边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的会话 fork 和消息顺序问题

# ══════════════════════════════════════════════
# Group 1: 会话 fork 与恢复（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: SESSION-ERR-001] TITLE: fork 后父会话内容不变 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="msg1"
GIVEN tape_append kind="assistant" content="reply1"
GIVEN tape_fork
THEN assert_entry_count expected=2

[SCENARIO: SESSION-ERR-002] TITLE: fork 后子会话保留用户消息 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="original"
GIVEN tape_fork
GIVEN tape_append kind="user" content="forked_msg"
THEN assert_entry_count expected=2

[SCENARIO: SESSION-ERR-003] TITLE: 恢复会话时消息顺序正确 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="first"
GIVEN tape_append kind="assistant" content="second"
GIVEN tape_append kind="user" content="third"
WHEN when_tape_init
THEN assert_entry_count expected=3
THEN assert_entry_order sequence="first,second,third"

[SCENARIO: SESSION-ERR-004] TITLE: 错误/中止消息在会话树中可见 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="error" content="something went wrong"
THEN assert_entry_count expected=1
THEN assert_entry_order sequence="something went wrong"

# ══════════════════════════════════════════════
# Group 2: Fork/Merge 和恢复（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: SESSION-ERR-005] TITLE: 待处理消息在 session 切换时被清理 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_add_pending content="pending message 1"
GIVEN tape_add_pending content="pending message 2"
WHEN tape_switch_session
THEN assert_pending_cleared

[SCENARIO: SESSION-ERR-006] TITLE: 异步事件 handler 错误被正确传播 TAGS: unit tape
GIVEN create_temp_dir
GIVEN register_failing_event_handler
WHEN emit_event event="test_event"
THEN assert_handler_error_propagated
