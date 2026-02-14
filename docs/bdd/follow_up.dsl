# Follow-up 消息队列 BDD 测试
# 覆盖 agent 完成后的自动下一轮和优先级

# ══════════════════════════════════════════════
# Group 1: Follow-up 消息队列 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: FOLLOWUP-001] TITLE: Agent 完成后有 follow_up 自动下一轮 TAGS: unit follow_up
GIVEN create_temp_dir
GIVEN inject_follow_up message="Please continue with step 2"
WHEN steering_check_follow_up
THEN assert_follow_up_message contains="step 2"

[SCENARIO: FOLLOWUP-002] TITLE: steering 和 follow_up 同时存在 steering 优先 TAGS: unit follow_up
GIVEN create_temp_dir
GIVEN inject_follow_up message="follow up task"
GIVEN push_steering_message message="urgent steering"
WHEN steering_check
THEN assert_steering_message contains="urgent steering"
WHEN steering_check_follow_up
THEN assert_follow_up_message contains="follow up task"

# ══════════════════════════════════════════════
# Group 2: Follow-up 补全 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: FOLLOWUP-003] TITLE: 空队列 check_follow_up 返回 nil TAGS: unit follow_up
GIVEN create_temp_dir
GIVEN steering_queue_empty
WHEN steering_check_follow_up
THEN assert_follow_up_empty

[SCENARIO: FOLLOWUP-004] TITLE: 多 follow_up 消息 FIFO 出队 TAGS: unit follow_up
GIVEN create_temp_dir
GIVEN inject_follow_up message="first follow up"
GIVEN inject_follow_up message="second follow up"
WHEN steering_check_follow_up
THEN assert_follow_up_message contains="first follow up"
WHEN steering_check_follow_up
THEN assert_follow_up_message contains="second follow up"

[SCENARIO: FOLLOWUP-005] TITLE: check_follow_up 跳过 steering 消息 TAGS: unit follow_up
GIVEN create_temp_dir
GIVEN push_steering_message message="steering msg"
GIVEN inject_follow_up message="follow up msg"
WHEN steering_check_follow_up
THEN assert_follow_up_message contains="follow up msg"
