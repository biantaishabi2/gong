# Compaction 上下文压缩 BDD 测试
# 阶段六：token 估算、滑动窗口、LLM 摘要、失败回退、并发锁、Tape 配合

# ══════════════════════════════════════════════
# Group 1: Token 估算（2 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-COMPACT-001] TITLE: 中英文混合 token 估算 TAGS: unit compaction
GIVEN compaction_messages count=5 token_size=100
WHEN when_estimate_tokens
THEN assert_token_estimate min=100 max=2000

[SCENARIO: BDD-COMPACT-002] TITLE: 空消息列表返回 0 TAGS: unit compaction
GIVEN compaction_messages count=0 token_size=0
WHEN when_estimate_tokens
THEN assert_token_estimate min=0 max=0

# ══════════════════════════════════════════════
# Group 2: 窗口策略（3 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-COMPACT-003] TITLE: 未超阈值不压缩 TAGS: unit compaction
GIVEN compaction_messages count=3 token_size=10
WHEN when_compact max_tokens=100000 window_size=5
THEN assert_not_compacted
THEN assert_summary_nil

[SCENARIO: BDD-COMPACT-004] TITLE: 超阈值触发压缩保留最近 N 条 TAGS: unit compaction
GIVEN compaction_messages count=10 token_size=500
GIVEN compaction_summarize_fn_ok
WHEN when_compact max_tokens=50 window_size=3
THEN assert_summary_exists
THEN assert_compacted message_count=4

[SCENARIO: BDD-COMPACT-005] TITLE: 系统消息始终保留不被压缩 TAGS: unit compaction
GIVEN compaction_messages_with_system count=10
GIVEN compaction_summarize_fn_ok
WHEN when_compact max_tokens=50 window_size=3
THEN assert_system_preserved
THEN assert_summary_exists

# ══════════════════════════════════════════════
# Group 3: 失败防护（3 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-COMPACT-006] TITLE: LLM 摘要失败回退到窗口裁剪 TAGS: unit compaction
GIVEN compaction_messages count=10 token_size=500
GIVEN compaction_summarize_fn_fail
WHEN when_compact max_tokens=50 window_size=3
THEN assert_summary_nil
THEN assert_compacted message_count=3

[SCENARIO: BDD-COMPACT-007] TITLE: 并发压缩被锁拒绝 TAGS: unit compaction
GIVEN compaction_lock_acquired session_id="test-session-1"
WHEN when_acquire_lock session_id="test-session-1"
THEN assert_compaction_error error_contains="compaction_in_progress"

[SCENARIO: BDD-COMPACT-008] TITLE: 压缩结果写入 Tape anchor TAGS: unit compaction
GIVEN create_temp_dir
GIVEN tape_init
GIVEN compaction_messages count=10 token_size=500
GIVEN compaction_summarize_fn_ok
WHEN when_compact_and_handoff max_tokens=50 window_size=3
THEN assert_tape_has_compaction_anchor
THEN assert_summary_exists

# ══════════════════════════════════════════════
# Group 4: 边界场景（6 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-COMPACT-009] TITLE: window_size 大于消息数不压缩 TAGS: unit compaction
GIVEN compaction_messages count=3 token_size=500
GIVEN compaction_summarize_fn_ok
WHEN when_compact max_tokens=50 window_size=10
THEN assert_summary_nil
THEN assert_not_compacted

[SCENARIO: BDD-COMPACT-010] TITLE: summarize_fn 抛异常回退到窗口裁剪 TAGS: unit compaction
GIVEN compaction_messages count=10 token_size=500
GIVEN compaction_summarize_fn_raise
WHEN when_compact max_tokens=50 window_size=3
THEN assert_summary_nil
THEN assert_compacted message_count=3

[SCENARIO: BDD-COMPACT-011] TITLE: 锁释放后可重新获取 TAGS: unit compaction
GIVEN compaction_lock_acquired session_id="reuse-session"
WHEN when_release_lock session_id="reuse-session"
WHEN when_acquire_lock session_id="reuse-session"
THEN assert_no_compaction_error

[SCENARIO: BDD-COMPACT-012] TITLE: 不同 session 锁互不干扰 TAGS: unit compaction
GIVEN compaction_lock_acquired session_id="session-a"
WHEN when_acquire_lock session_id="session-b"
THEN assert_no_compaction_error

[SCENARIO: BDD-COMPACT-013] TITLE: window_size=0 只保留系统消息和摘要 TAGS: unit compaction
GIVEN compaction_messages_with_system count=10
GIVEN compaction_summarize_fn_ok
WHEN when_compact max_tokens=50 window_size=0
THEN assert_summary_exists
THEN assert_system_preserved

[SCENARIO: BDD-COMPACT-014] TITLE: 回退后含系统消息的窗口裁剪 TAGS: unit compaction
GIVEN compaction_messages_with_system count=10
GIVEN compaction_summarize_fn_fail
WHEN when_compact max_tokens=50 window_size=3
THEN assert_summary_nil
THEN assert_system_preserved
THEN assert_compacted message_count=4
