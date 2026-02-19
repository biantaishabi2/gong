Feature: CLI 接入 Session 归一事件流
  为了让前端稳定消费异步 steer 结果
  作为 CLI 与 Session 的集成方
  我希望命令统一进入 Session stream，并遵守顺序与订阅语义

  Scenario: 同一 session 内并发 steer 命令保持可预测顺序
    Given 已存在 session "session-1"
    And 已通过 CLI 订阅 session "session-1" 事件流
    When CLI 并发提交 steer 命令 "A" "B" "C"
    Then 每个 command 内事件顺序严格
    And session 级 seq 单调递增
    And 前端按 event_id 去重后状态无丢失

  Scenario: 订阅中途取消后不再接收新事件
    Given 已存在 session "session-2"
    And 订阅者 "client-a" 正在消费事件流
    When "client-a" 执行 unsubscribe
    And CLI 继续向 "session-2" 提交新命令
    Then "client-a" 不再收到新事件
    And session 内在途命令可继续完成
    And 其他订阅者消费不受影响

  Scenario: 非法 command payload 被 CLI 拒绝
    Given 已存在 session "session-3"
    When CLI 提交缺失 session_id 的命令
    Then CLI 返回 invalid_argument 错误
    And 提供可修复提示

  Scenario: 消费端检测重复或逆序 seq 触发恢复策略
    Given 消费端已保存 last_seq 检查点
    When 收到重复 seq 或逆序 seq 事件
    Then 触发顺序校验错误
    And 执行重拉或缓冲重排策略
