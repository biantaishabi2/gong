# Steering 中断机制 BDD 测试
# 工具执行间隙检查 steering 消息，有则跳过剩余工具

[SCENARIO: BDD-STEER-001] TITLE: steering 消息入队出队 TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_push message="中断请求"
THEN assert_steering_pending
WHEN steering_check
THEN assert_steering_message contains="中断请求"
THEN assert_steering_empty

[SCENARIO: BDD-STEER-002] TITLE: steering 跳过结果格式 TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_skip_result tool="bash"
THEN assert_steering_skip_contains text="Skipped"
THEN assert_steering_skip_contains text="bash"

# ── 2. Steering unit 补全 ──

[SCENARIO: BDD-STEER-003] TITLE: 空队列 check 返回 nil TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_check
THEN assert_steering_message_nil

[SCENARIO: BDD-STEER-004] TITLE: pending? 空队列返回 false TAGS: unit agent_loop
GIVEN steering_queue_empty
THEN assert_steering_not_pending

[SCENARIO: BDD-STEER-005] TITLE: 多消息 FIFO 出队 TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_push message="first"
WHEN steering_push message="second"
WHEN steering_check
THEN assert_steering_message contains="first"
WHEN steering_check
THEN assert_steering_message contains="second"

[SCENARIO: BDD-STEER-006] TITLE: typed steering 消息入队出队 TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_push_typed type="steering" message="urgent"
WHEN steering_check
THEN assert_steering_message contains="urgent"

[SCENARIO: BDD-STEER-007] TITLE: check 跳过 follow_up 只取 steering TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_push_typed type="follow_up" message="later"
WHEN steering_push_typed type="steering" message="now"
WHEN steering_check
THEN assert_steering_message contains="now"

[SCENARIO: BDD-STEER-008] TITLE: check_steering 等价于 check TAGS: unit agent_loop
GIVEN steering_queue_empty
WHEN steering_push message="via_check_steering"
WHEN steering_check_steering
THEN assert_steering_message contains="via_check_steering"
