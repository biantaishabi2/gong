# Gong BDD 覆盖缺口分析（基于 pi-mono bugfix 历史）

生成时间：2026-02-16
数据源：172 条 pi-mono bugfix specs × 49 个 gong BDD DSL 文件（530+ 场景）

## 方法

逐条比对 `by_module/*.json` 中的 bug 模式与 gong `docs/bdd/*.dsl` 中的已有场景，
过滤掉 gong 不涉及的纯前端/TUI/TypeScript 特有模块（约 25 个），
仅保留 **gong 有对应功能但 BDD 未覆盖该 bug 模式** 的缺口。

---

## P0: 运行时稳定性（6 个）

| # | pi-mono commit | 模块 | bug 模式 | gong 对应 | 现有覆盖 | 缺口 |
|---|---------------|------|---------|----------|---------|------|
| 1 | fb6d464 | agent-session | `isRetryableError` 遗漏 `fetch failed` | retry.dsl | RETRY-004 仅覆盖 ECONNREFUSED | 补充 `fetch failed` 错误模式匹配 |
| 2 | c138281 | agent-session | `isRetryableError` 遗漏 `connection error` | retry.dsl | RETRY-004 覆盖具体 ECONNREFUSED，不覆盖泛化 `connection error` | 补充泛化 `connection error` 模式 |
| 3 | 9b84857 | agent-session | `isRetryableError` 遗漏 `terminated` | retry.dsl | 无 | 补充 `terminated` 错误模式匹配 |
| 4 | e30c4e3 | agent-session | `getLastAssistantMessage` 未跳过 aborted 空消息 | agent_integration.dsl | 无 | 补充 aborted+空内容的 assistant 消息跳过逻辑 |
| 5 | 9e86079 | google | 流式 `contentIndex` 在 push 前发送 start 事件 | stream_edge.dsl | 无 | 补充 content block index 与实际位置一致性校验 |
| 6 | 6ddfd1b | bash-executor | UTF-8 多字节字符跨 chunk 切分乱码 | bash_edge.dsl | 无 | 补充 UTF-8 多字节流式解码场景（中文跨 chunk） |

## P1: 跨 Provider 正确性（7 个）

| # | pi-mono commit | 模块 | bug 模式 | gong 对应 | 现有覆盖 | 缺口 |
|---|---------------|------|---------|----------|---------|------|
| 7 | 0138eee | anthropic | `ls` 工具名映射错误（Glob→Ls） | cross_provider.dsl | CROSS-005 测试 tool_calls 转换但不测工具名映射 | 补充工具名映射正确性回归测试 |
| 8 | 7a41975 | google-shared | Claude 经 Google API 调用缺 `tool_call_id` | cross_provider.dsl | CROSS-005 不验证 id 字段 | 补充跨 provider tool_call_id 保留校验 |
| 9 | 289e60a | gemini | thinking config 错误嵌套在 `config.config` 下 | thinking.dsl | 无 config 层级校验 | 补充 thinking config 结构正确性（顶层 vs 嵌套） |
| 10 | 4f9dedd + cceb590 | ai / openai-completions | compat 检测遗漏特定域名（DeepSeek/OpenCode） | cross_provider.dsl | 无 URL 兼容检测 | 补充 provider compat URL 匹配覆盖 |
| 11 | 7db3068 | openai-responses | provider 完成后未调用 `calculateCost` | cost_tracking.dsl | COST-001~007 测 tracker 本身，不测 provider 端到端 | 补充 provider→cost_tracker 端到端成本记录 |
| 12 | a613306 | openai-completions | 工具 schema `strict:false` 缺失 | tool_config.dsl | 无 strict 模式测试 | 补充工具 schema strict 模式配置校验 |
| 13 | 0fc6689 | anthropic | SDK `maxRetries:0` 禁用了自动重试 | provider.dsl | 无 SDK 重试配置测试 | 补充 provider SDK 重试策略不被意外禁用 |

## P2: 会话/存储正确性（6 个）

| # | pi-mono commit | 模块 | bug 模式 | gong 对应 | 现有覆盖 | 缺口 |
|---|---------------|------|---------|----------|---------|------|
| 14 | 754f55e | session-manager | compaction kept 区间未处理 `branch_summary` 条目 | compaction.dsl + branch_summary.dsl | COST-ERR-004~006 测压缩边界，不测 branch_summary 在 kept 区间 | 补充 compaction 保留区间含 branch_summary 的处理 |
| 15 | b5be54b | session-manager | 分叉后仅有 user 消息时 flush 未重置 `flushed` 标记 | session_edge.dsl | 无 | 补充分叉后仅 user 消息的 flush 行为 |
| 16 | 98c85bf | sdk | 新会话未持久化初始 model 和 thinkingLevel | tape_session.dsl | 无初始状态持久化测试 | 补充新会话创建时初始模型/思考级别的持久化 |
| 17 | 92947a3 | branch-summarization | 正向遍历找公共祖先选到最浅而非最深 | branch_summary.dsl | 无祖先深度测试 | 补充多层分支的最深公共祖先校验 |
| 18 | ecef601 | session-manager | Hook 消息 role 被映射为 `user` 而非 `hookMessage` | hook_system.dsl | BDD-HOOK-011~014 测 on_context/on_input 但不测消息 role 映射 | 补充 Hook 消息 role 类型校验 |
| 19 | 574f1cb | messages | HookMessage content 为字符串时未归一化为数组 | hook_system.dsl | 无 content 格式归一化测试 | 补充 Hook 消息 content 字符串→数组归一化 |

## P3: 扩展/配置正确性（13 个）

| # | pi-mono commit | 模块 | bug 模式 | gong 对应 | 现有覆盖 | 缺口 |
|---|---------------|------|---------|----------|---------|------|
| 20 | 31438fd | sdk | 仅对激活工具做 hook 包装，非激活工具绕过 hook | hook_system.dsl | BDD-HOOK-004~006 测拦截链但工具都是激活的 | 补充非激活注册工具的 hook 包装覆盖 |
| 21 | d89f6e0 | coding-agent | git URL 未去除 `.git` 后缀导致归一化 key 不一致 | extension.dsl | 无 URL 归一化 | 补充扩展源 git URL 归一化（去协议、去 .git） |
| 22 | b74a365 | coding-agent | 扩展加载失败后未输出具体错误信息 | extension.dsl | EXTEND-004 测隔离但不测错误日志输出 | 补充扩展加载失败的错误日志输出校验 |
| 23 | 88ac5ca | coding-agent | `.pi/...` 路径未识别为本地路径 | extension.dsl | 无路径前缀检测 | 补充扩展源 `.` 前缀路径识别为本地 |
| 24 | e4f6358 | coding-agent | 扩展路径仅来自 CLI 参数，未合并 settings.json | extension.dsl | 无 settings 合并 | 补充 CLI 参数 + settings.json 扩展路径合并加载 |
| 25 | c9a20a3 | extensions | `@` 前缀路径未被标准化 | extension.dsl | 无 | 补充 `@` 前缀路径归一化处理 |
| 26 | e68058c | extensions-runner | 扩展上下文 model 为创建时快照，切换后不更新 | extension.dsl | 无动态 model 测试 | 补充扩展上下文 model 动态更新（getter vs 快照） |
| 27 | 5c047c3 | resource-loader | 冲突扩展仅记录错误但未从列表移除 | hook_edge.dsl | EXT-ERR-003 测冲突检测但不测移除 | 补充冲突扩展从已加载列表中移除 |
| 28 | a9a1a62 | system-prompt | 全局 AGENTS.md 与遍历路径未去重 | resource.dsl | 无路径去重测试 | 补充上下文文件路径去重 |
| 29 | 0fe9f74 | settings-manager | getter 返回内部引用，外部修改污染内部状态 | settings.dsl | SETTINGS-003 测运行时修改但不测引用隔离 | 补充 settings getter 返回副本不可变性 |
| 30 | 6201bae | coding-agent | systemPrompt + appendSystemPrompt 合并为函数而非字符串 | prompt_template.dsl | 无合并测试 | 补充 system prompt + append prompt 字符串合并 |
| 31 | 958d265 | coding-agent | RPC prompt 未透传 attachments | rpc.dsl | RPC-001~007 不测附件透传 | 补充 RPC prompt 附件透传校验 |
| 32 | 2e1c5eb | models | xhigh 能力判断用精确匹配，新变体被误判 | model_registry.dsl | MODEL-001~009 不测能力模糊匹配 | 补充模型能力判断使用 contains 而非精确匹配 |

---

## 汇总

| 优先级 | 数量 | 领域 |
|--------|------|------|
| P0 | 6 | 重试模式、流式索引、Bash UTF-8 |
| P1 | 7 | 工具名映射、tool_call_id、thinking config、compat 检测、成本计算、schema strict、SDK 重试 |
| P2 | 6 | compaction branch_summary、fork flush、初始状态持久化、分支祖先、Hook 消息 role/content |
| P3 | 13 | 扩展路径/加载/上下文、settings 副本、prompt 合并、RPC 附件、模型能力匹配 |
| **合计** | **32** | |

## 下一步

```bash
# 按优先级补充 BDD 场景到对应 DSL 文件
# P0 → retry.dsl, stream_edge.dsl, bash_edge.dsl, agent_integration.dsl
# P1 → cross_provider.dsl, cross_provider_edge.dsl, thinking_edge.dsl, cost_edge.dsl, tool_config.dsl, provider_edge.dsl
# P2 → compaction.dsl, session_edge.dsl, tape_session.dsl, branch_summary.dsl, hook_edge.dsl
# P3 → extension.dsl, hook_edge.dsl, settings.dsl, prompt_template.dsl, rpc.dsl, model_registry.dsl, resource.dsl
```
