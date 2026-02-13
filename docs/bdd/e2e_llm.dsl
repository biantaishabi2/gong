# E2E LLM 真实调用测试
# 需要 API key，默认通过 @tag :e2e 排除
# 运行方式：mix test --include e2e

# ══════════════════════════════════════════════
# Group 1: 冒烟测试 (3 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-001] TITLE: DeepSeek 简单问答 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="1+1等于几？请只回答数字"
THEN assert_agent_reply contains="2"
THEN assert_no_crash

[SCENARIO: BDD-E2E-002] TITLE: 数学推理 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="一个长方形长5cm宽3cm，面积是多少平方厘米？请只回答数字"
THEN assert_agent_reply contains="15"
THEN assert_no_crash

[SCENARIO: BDD-E2E-003] TITLE: 中文理解 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="请用一个成语形容非常开心，只回答成语本身"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 2: 工具调用 (3 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-004] TITLE: LLM 自主选择读文件工具 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="info.txt" content="Gong版本号是v0.42"
GIVEN configure_agent
WHEN agent_chat prompt="读取 info.txt 的内容，告诉我版本号"
THEN assert_tool_was_called tool="read_file"
THEN assert_agent_reply contains="0.42"
THEN assert_no_crash

[SCENARIO: BDD-E2E-005] TITLE: LLM 自主选择写文件工具 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="在当前目录创建 greeting.txt，内容写 hello e2e test"
THEN assert_tool_was_called tool="write_file"
THEN assert_file_exists path="greeting.txt"
THEN assert_file_content path="greeting.txt" expected="hello e2e test"
THEN assert_no_crash

[SCENARIO: BDD-E2E-006] TITLE: LLM 链式调用多个工具 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="source.txt" content="alpha beta gamma"
GIVEN configure_agent
WHEN agent_chat prompt="先读 source.txt，然后把 beta 替换成 BETA，最后读取修改后的文件确认结果"
THEN assert_tool_was_called tool="read_file"
THEN assert_file_content path="source.txt" expected="alpha BETA gamma"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 3: 多轮对话 (2 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-007] TITLE: 两轮对话上下文保持 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="请记住这个数字：7749"
WHEN agent_chat_continue prompt="我刚才让你记住的数字是什么？请只回答数字"
THEN assert_agent_reply contains="7749"
THEN assert_no_crash

[SCENARIO: BDD-E2E-008] TITLE: 三轮渐进任务 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="在当前目录创建 todo.txt，内容写 buy milk"
THEN assert_file_exists path="todo.txt"
WHEN agent_chat_continue prompt="读一下 todo.txt 的内容"
THEN assert_agent_reply contains="buy milk"
WHEN agent_chat_continue prompt="把 todo.txt 里的 milk 改成 coffee"
THEN assert_file_content path="todo.txt" expected="buy coffee"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 4: 错误恢复 (2 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-009] TITLE: LLM 工具调用失败后自行恢复 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="real.txt" content="recovery success"
GIVEN configure_agent
WHEN agent_chat prompt="先尝试读取 nonexistent.txt，如果失败就读取 real.txt，告诉我最终读到的内容"
THEN assert_agent_reply contains="recovery success"
THEN assert_no_crash

[SCENARIO: BDD-E2E-010] TITLE: 不存在文件的错误处理 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="读取 does_not_exist.txt 的内容"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 5: 性能边界 (2 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-011] TITLE: 大文件读取 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_large_file lines=500 path="big.txt" line_length=80
GIVEN configure_agent
WHEN agent_chat prompt="读取 big.txt 的内容，告诉我大概有多少行"
THEN assert_tool_was_called tool="read_file"
THEN assert_no_crash

[SCENARIO: BDD-E2E-012] TITLE: 长 prompt 处理 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="请分析以下需求并给出简短回答：我们需要构建一个分布式消息队列系统，支持发布订阅模式、消息持久化、消息确认机制、死信队列、延迟消息、消息优先级、消息路由、消息过滤、消息回溯、消息追踪。请只回答：收到，已了解需求。"
THEN assert_agent_reply contains="收到"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 6: Compaction 触发性 (1 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-013] TITLE: 多轮对话后检查 Compaction 可触发性 TAGS: e2e agent
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
WHEN agent_chat prompt="创建 a.txt 内容为 hello"
WHEN agent_chat_continue prompt="创建 b.txt 内容为 world"
WHEN agent_chat_continue prompt="创建 c.txt 内容为 test"
THEN assert_file_exists path="a.txt"
THEN assert_file_exists path="b.txt"
THEN assert_file_exists path="c.txt"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 7: Hook 拦截 (3 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-014] TITLE: Hook 拦截 bash — BlockBash hook 阻止 bash 工具 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="BlockBash"
WHEN agent_chat_live prompt="用 bash 执行 echo hello 并告诉我结果"
THEN assert_no_crash

[SCENARIO: BDD-E2E-015] TITLE: Hook 脱敏 — RedactApiKey 替换工具结果中的密钥 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="secret.txt" content="api_key=sk_test_AbCdEfGhIjKlMnOpQrStUvWxYz123456"
GIVEN configure_agent
GIVEN register_hook module="RedactApiKey"
WHEN agent_chat_live prompt="读取 secret.txt 的内容，告诉我 api_key 的值"
THEN assert_agent_reply contains="REDACTED"
THEN assert_no_crash

[SCENARIO: BDD-E2E-016] TITLE: Hook 崩溃不影响 — CrashHook 抛异常但循环继续 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="safe.txt" content="hook crash test ok"
GIVEN configure_agent
GIVEN register_hook module="CrashHook"
WHEN agent_chat_live prompt="读取 safe.txt 的内容"
THEN assert_agent_reply contains="hook crash test ok"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 8: Hook 变换 (2 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-017] TITLE: on_context 注入 — InjectContext hook 注入安全策略 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="InjectContext"
WHEN agent_chat_live prompt="你的系统消息里有什么安全相关的内容？"
THEN assert_no_crash

[SCENARIO: BDD-E2E-018] TITLE: on_input 变换 — TransformInput hook 给输入加前缀 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN configure_agent
GIVEN register_hook module="TransformInput"
WHEN agent_chat_live prompt="请回复收到"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 9: Hook + 多轮 (1 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-019] TITLE: Hook 在多轮对话中持续生效 TAGS: e2e agent hook
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="key1.txt" content="secret=sk_live_RealKeyHere123456789012"
GIVEN create_temp_file path="key2.txt" content="token=sk_test_AnotherKey9876543210AB"
GIVEN configure_agent
GIVEN register_hook module="RedactApiKey"
WHEN agent_chat_live prompt="读取 key1.txt 的内容"
THEN assert_agent_reply contains="REDACTED"
WHEN agent_chat_live prompt="读取 key2.txt 的内容"
THEN assert_agent_reply contains="REDACTED"
THEN assert_no_crash

# ══════════════════════════════════════════════
# Group 10: Telemetry 事件序列 (1 个)
# ══════════════════════════════════════════════

[SCENARIO: BDD-E2E-020] TITLE: 真实调用下 telemetry 事件序列正确 TAGS: e2e agent telemetry
GIVEN check_e2e_provider provider="deepseek"
GIVEN create_temp_dir
GIVEN create_temp_file path="tel.txt" content="telemetry test"
GIVEN configure_agent
GIVEN attach_telemetry_handler event="gong.agent.start"
GIVEN attach_telemetry_handler event="gong.tool.start"
GIVEN attach_telemetry_handler event="gong.tool.stop"
GIVEN attach_telemetry_handler event="gong.agent.end"
WHEN agent_chat_live prompt="读取 tel.txt"
THEN assert_telemetry_received event="gong.agent.start"
THEN assert_telemetry_received event="gong.tool.start" metadata_contains="read_file"
THEN assert_telemetry_received event="gong.tool.stop" metadata_contains="read_file"
THEN assert_telemetry_received event="gong.agent.end"
THEN assert_no_crash
