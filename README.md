# Gong (工)

[![CI](https://github.com/biantaishabi2/gong/actions/workflows/ci.yml/badge.svg)](https://github.com/biantaishabi2/gong/actions/workflows/ci.yml)

通用 Agent 引擎 — 基于 Elixir/OTP 的自主编码代理框架。

## 项目背景

本项目受 [pi-mono](https://github.com/badlogic/pi-mono)（Mario Zechner 的 TypeScript AI Agent 工具集）启发，用 Elixir 重新实现了编码代理的核心架构。感谢 pi-mono 项目提供的优秀设计思路和参考实现。

与 pi-mono 的 TypeScript 方案不同，Gong 利用 Elixir/OTP 的进程隔离、容错和并发能力来构建 Agent 运行时，并基于 [Jido](https://github.com/agentjido/jido) + [ReqLLM](https://hex.pm/packages/req_llm) 生态。

## 核心功能

- **ReAct Agent 循环** — LLM 推理 + 工具调用的自动状态机循环
- **7 个内置工具** — read / write / edit / bash / grep / find / ls
- **Hook 系统** — 拦截（before_tool_call）、变换（on_tool_result / on_context / on_input）、注入（on_before_agent），支持安全策略、脱敏、审计
- **上下文压缩（Compaction）** — 滑动窗口 + LLM 摘要，自动管理长对话的 token 预算
- **Steering 中断** — 运行时向 Agent 注入指令，改变执行方向
- **会话存储（Tape）** — 文件夹 + SQLite 索引的持久化会话记录
- **输出截断** — head / tail / line 三种策略，防止大输出冲爆上下文
- **自动重试** — 错误分类 + 指数退避重试
- **Telemetry 集成** — agent.start / tool.start / tool.stop / agent.end 全链路事件

## 架构

```
Gong.Agent          — Jido ReActAgent 定义（工具集 + 模型 + 系统提示词）
Gong.Tools.*        — 7 个 Jido Action（read/write/edit/bash/grep/find/ls）
Gong.HookRunner     — Hook 执行引擎（gate 拦截 + pipe 变换，5s 超时保护）
Gong.Compaction     — 上下文压缩（配对保护 + 结构化摘要）
Gong.Steering       — 运行时中断队列
Gong.Tape.*         — 会话存储（FileStore + SQLite Index）
Gong.Truncate       — 输出截断系统
Gong.Retry          — 错误分类 + 重试策略
Gong.Providers.*    — LLM Provider（DeepSeek，OpenAI 兼容）
```

## 快速开始

```bash
# 安装依赖
mix setup

# 运行测试（不含 E2E）
mix test

# 运行 E2E 测试（需要 API key）
DEEPSEEK_API_KEY=your_key mix test --include e2e
```

## BDD 测试

项目使用自研 BDD DSL 编写测试场景，通过 `bddc` 编译器生成 ExUnit 测试：

```bash
# 编译 BDD DSL → ExUnit 测试文件
bddc compile

# 运行生成的 BDD 测试
mix test test/bdd_generated/
```

当前覆盖 **439 测试场景**，包括：
- 工具单元测试（read / write / edit / bash / grep / find / ls）
- Hook 系统测试（拦截 / 变换 / 崩溃容错 / 超时保护）
- Agent 集成测试（mock LLM 驱动的完整 ReAct 循环）
- Compaction / Steering / Retry 机制测试
- E2E 真实 LLM 测试（20 个场景，含 Hook + Telemetry 深层功能验证）

## 致谢

- [pi-mono](https://github.com/badlogic/pi-mono) — Mario Zechner 的 AI Agent 工具集，本项目的灵感来源
- [Jido](https://github.com/agentjido/jido) — Elixir Agent 框架
- [ReqLLM](https://hex.pm/packages/req_llm) — 多 Provider LLM 客户端

## License

MIT
