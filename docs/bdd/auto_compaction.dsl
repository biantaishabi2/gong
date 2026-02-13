# Auto-Compaction 自动压缩 BDD 测试
# Agent 循环自动检测上下文溢出并压缩

[SCENARIO: BDD-AUTOCOMPACT-001] TITLE: 上下文超限自动触发压缩 TAGS: unit agent_loop
GIVEN compaction_messages count=20 token_size=500
GIVEN compaction_summarize_fn_ok
WHEN auto_compact context_window=2000 reserve_tokens=500 window_size=5
THEN assert_auto_compacted

[SCENARIO: BDD-AUTOCOMPACT-002] TITLE: 上下文未超限不压缩 TAGS: unit agent_loop
GIVEN compaction_messages count=3 token_size=10
WHEN auto_compact context_window=200000 reserve_tokens=16384 window_size=5
THEN assert_auto_no_action

[SCENARIO: BDD-AUTOCOMPACT-003] TITLE: 压缩期间 steering 队列消息保留 TAGS: unit agent_loop
GIVEN steering_queue_empty
GIVEN compaction_messages count=20 token_size=500
GIVEN compaction_summarize_fn_ok
WHEN steering_push message="新用户消息"
WHEN auto_compact context_window=2000 reserve_tokens=500 window_size=5
THEN assert_auto_compacted
THEN assert_steering_pending
