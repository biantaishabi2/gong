# Cost/Token 追踪 BDD 测试
# 覆盖调用记录、累计统计、历史查询

# ══════════════════════════════════════════════
# Group 1: Cost 追踪（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: COST-001] TITLE: 记录单次 LLM 调用 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="deepseek-chat" input_tokens=100 output_tokens=50
THEN assert_cost_summary call_count=1

[SCENARIO: COST-002] TITLE: 累计多次调用统计 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="deepseek-chat" input_tokens=100 output_tokens=50
WHEN record_llm_call model="deepseek-chat" input_tokens=200 output_tokens=100
THEN assert_cost_summary call_count=2 total_input=300 total_output=150

[SCENARIO: COST-003] TITLE: 最近一次调用记录 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="gpt-4" input_tokens=500 output_tokens=200
THEN assert_last_call model="gpt-4"

[SCENARIO: COST-004] TITLE: 重置后清空历史 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_llm_call model="deepseek-chat" input_tokens=100 output_tokens=50
WHEN reset_cost_tracker
THEN assert_cost_summary call_count=0
