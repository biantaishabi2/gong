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
