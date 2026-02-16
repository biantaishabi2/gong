# 令牌/成本边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的限流、overflow 和流中断令牌计数

# ══════════════════════════════════════════════
# Group 1: 错误分类与成本（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: COST-ERR-003] TITLE: 流中断保留令牌计数 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="claude-3" input_tokens=100 output_tokens=50
WHEN reset_cost_tracker
THEN assert_cost_summary call_count=0

# ══════════════════════════════════════════════
# Group 2: 压缩边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: COST-ERR-004] TITLE: 压缩 cut point 不越过 session header TAGS: unit compaction
GIVEN create_temp_dir
GIVEN compaction_messages_with_session_header count=8 header_at=3
GIVEN compaction_summarize_fn_ok
WHEN when_compact max_tokens=50 window_size=3
THEN assert_compacted message_count=4
THEN assert_session_header_preserved

[SCENARIO: COST-ERR-005] TITLE: 分支摘要保留工具调用结构 TAGS: unit compaction
GIVEN create_temp_dir
GIVEN compaction_messages_with_tool_calls count=6
GIVEN compaction_summarize_fn_ok
WHEN compact_with_tool_calls max_tokens=50 window_size=3
THEN assert_summary_has_tool_calls

[SCENARIO: COST-ERR-006] TITLE: 切换模型后旧模型 overflow 不误触发新模型压缩 TAGS: unit compaction
GIVEN create_temp_dir
GIVEN init_model_registry
GIVEN register_model name="old_model" provider="openai" model_id="gpt-4"
GIVEN register_model name="new_model" provider="anthropic" model_id="claude-3"
WHEN trigger_overflow_on_model model="old_model"
WHEN switch_model_after_overflow new_model="new_model"
THEN assert_no_compaction_on_new_model

# ══════════════════════════════════════════════
# Group 3: pi-mono bugfix 回归（1 场景）
# ══════════════════════════════════════════════

[SCENARIO: COST-ERR-007] TITLE: provider 调用完成后自动记录成本 (Pi#7db3068) TAGS: unit cost regression
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="claude-3" input_tokens=200 output_tokens=80
THEN assert_cost_summary call_count=1 total_input=200 total_output=80
