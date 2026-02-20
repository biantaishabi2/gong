# OpenClaw Gateway 架构分析

基于 `Cli/compiler/bcc/examples/openclaw-arch/` 的完整分析，提取多通道消息网关的核心模式，供后续独立项目参考。

---

## 一、OpenClaw 是什么

OpenClaw 是一个**多通道 AI 消息网关**（multi-channel AI message gateway），核心功能是把来自不同消息渠道（飞书、Discord、Slack、Telegram 等）的消息路由到正确的 Agent 运行时，再把 Agent 的输出格式化后推回渠道。

它不是编码 Agent 本身，而是 Agent 的**接入层和调度层**。

---

## 二、核心模块划分

OpenClaw 的架构经历了 v0→v3 的演进，最终收敛为 7 个模块：

| 模块 | 职责 | 优先级 |
|------|------|--------|
| `gateway_control_plane` | 网关控制面：协议、路由、会话 | 10（最高） |
| `agent_runtime` | Agent 运行时：执行、状态 | 20 |
| `channel_ingress` | 渠道接入：协议适配、消息收发 | 30 |
| `plugin_tool_extension` | 插件/工具扩展 | 40 |
| `foundation_infra` | 基础设施：配置、日志、存储 | 50 |
| `ops_client_entry` | 运营入口：CLI、管理面板 | 60 |
| `external_dependencies` | 外部依赖适配 | 70 |

### 模块边界（Gateway 为例）

```
gateway_control_plane:
  include:
    - src/gateway/**        # 核心网关逻辑
    - src/routing/**        # 会话路由/解析
    - src/sessions/**       # 会话状态管理
    - src/pairing/**        # 设备/客户端配对
  exclude:
    - **/*.test.ts
    - **/*.spec.ts
```

---

## 三、Gateway 的核心职责

### 3.1 协议层

Gateway 定义了三个关键合约：

1. **WebSocket 帧协议** (`gateway-ws-frame-contract`) — 客户端↔网关通信的消息帧格式
2. **流式响应事件** (`responses-stream-event-contract`) — Agent 输出的 SSE/流式事件格式
3. **客户端状态机** (`ws-client-state-contract`) — 连接生命周期和状态管理

### 3.2 路由层

```
渠道消息进入
    ↓
routing/session-key.ts   (提取会话上下文：租户、用户、渠道)
    ↓
routing/resolve-route.ts (决定目标 Agent)
    ↓
sessions/*               (维护会话状态)
    ↓
Agent 分发
```

**session-key 是整个系统的路由核心**，被 70+ 文件引用。它从渠道消息中提取出统一的会话标识，让 Gateway 能把不同渠道的消息映射到同一个 Agent 会话。

### 3.3 消息流向

```
入站：Channel → Gateway → Agent
──────────────────────────────
channel_ingress (72 edges)
    ↓
gateway_control_plane (session-key → route → dispatch)
    ↓ (44 edges)
agent_runtime

出站：Agent → Channel → 外部平台
──────────────────────────────────
agent_runtime
    ↓ (73 edges，输出绑定渠道语义)
channel_ingress
    ↓
外部消息平台 (飞书/Slack/Discord/...)
```

### 3.4 配置

```typescript
// gateway-config-contract
interface GatewayConfig {
  bind_to: string      // 绑定地址
  tls: TLSConfig       // TLS/SSL
  discovery: Discovery  // 服务发现
  nodes: NodeConfig     // 集群节点
  remotes: Remote[]     // 远程配置源
  http: HTTPEndpoints   // HTTP 端点
}
```

---

## 四、依赖规则

### 允许的依赖方向

```
gateway_control_plane
    ↓ depends on
    ├── agent_runtime        (分发请求)
    ├── channel_ingress      (协调渠道操作)
    ├── foundation_infra     (配置、日志)
    ├── platform_hosts       (集成宿主入口)
    └── plugin_tool_extension (插件启动/调用)
```

### 谁可以依赖 Gateway

```
channel_ingress      → gateway (72 edges, 路由/会话解析)
agent_runtime        → gateway (44 edges, 读写会话路由)
plugin_tool_extension → gateway (40 edges, 会话/路由控制)
ops_client_entry     → gateway (运营控制网关)
```

### 禁止的方向

- `foundation_infra` 不能依赖 `gateway`（下层不能依赖上层）
- `external_dependencies` 不能依赖任何业务模块

---

## 五、V2→V3 重构教训

### 问题 A：运营入口当工具库用

ops_client_entry 里的 CLI 格式化工具被 Gateway 导入。
**解法**：提取 `shared_kernel` 模块放公共工具。

### 问题 B：session-key 放错位置

`routing/session-key.ts` 放在 Gateway 里，但 foundation_infra 也需要它，导致下层依赖上层。
**解法**：把 session-key 下沉到 `foundation_infra`，作为共享合约。

### 问题 C：barrel export 传递耦合

`plugin-sdk/index.ts` re-export 了渠道类型，导致 121 个文件级别的传递依赖。
**解法**：定义 Port 接口，渠道实现适配器，打断传递链。

### 问题 D：外部依赖反向引用

Provider 直接 import 了 runtime 的 `auth-profiles.ts`。
**解法**：引入 `AuthPort`、`HostPort` 抽象接口。

### 量化效果

| 指标 | v0 | v3 目标 |
|------|----|---------|
| 有向边密度 | 75% | 40% |
| 双向依赖对 | 20 | 5 |
| 禁止边 | 5 | 0 |

---

## 六、关键设计模式总结

1. **Port/Adapter 模式** — Gateway 定义 Port 接口（协议合约），各渠道实现 Adapter
2. **Session-Key 作为共享合约** — 会话标识是跨模块的统一语言，放在基础设施层
3. **单向依赖** — 上层依赖下层，永远不反过来
4. **协议合约驱动** — 先定义帧格式、事件格式、状态机，再写实现
5. **渠道语义绑定** — Agent 输出绑定到渠道语义（Markdown → 飞书卡片 / Slack Block），不是裸文本透传

---

## 七、与 Gong 的关系

### 7.1 分工

```
Gong (工) — 编码 Agent 引擎（PI 层）
├── Agent + AgentLoop (ReAct 循环)
├── Session (会话协调、事件流)
├── Tools (7 个工具)
├── Hook/Extension 系统
├── Storage/Compaction
└── CLI (交互入口)

Gateway 项目（独立） — 消息网关（接入层）
├── Protocol (帧协议、事件合约)
├── Routing (session-key、路由解析)
├── Channel Adapters (飞书/Slack/...)
├── Config (网关配置)
└── Ops (管理面板)
```

**Gong 是 Agent 引擎，Gateway 是接入基础设施。** Gong 不关心消息从哪个渠道来；Gateway 不关心 Agent 内部怎么执行。

### 7.2 集成点

```
Gateway ──调用──→ Gong.Session API
                   ├── Session.start_link/1   (创建会话)
                   ├── Session.prompt/2       (提交消息)
                   ├── Session.subscribe/2    (订阅事件流)
                   ├── Session.history/1      (获取历史)
                   └── Session.restore/2      (恢复会话)
```

Gateway 是 Gong Session 的**消费者**：

1. 渠道消息进来 → Gateway 通过 session-key 找到（或创建）Gong Session
2. Gateway 调用 `Session.prompt/2` 提交用户消息
3. Gateway 订阅 Session 事件流，把 `message.delta` 转换为渠道格式推送
4. 会话结束时 Gateway 处理 `lifecycle.completed` 事件

### 7.3 不需要改 Gong 的地方

Gong 的 Session API 已经是标准的事件驱动接口（subscribe → 接收 `{:session_event, event}`），Gateway 只需要适配这个接口，不需要修改 Gong 内部。

### 7.4 集成边界合约

```elixir
# Gateway 看到的 Gong 接口（已有）
Gong.Session.start_link(opts)           # → {:ok, pid}
Gong.Session.prompt(pid, message)       # → :ok
Gong.Session.subscribe(pid, self())     # → :ok
Gong.Session.history(pid)               # → {:ok, events}
Gong.Session.close(pid)                 # → :ok

# Gateway 收到的事件格式（已有）
{:session_event, %{
  type: "message.delta",
  payload: %{content: "..."},
  session_id: "...",
  command_id: "...",
  seq: 3
}}
```

### 7.5 后续独立项目规划

Gateway 作为独立项目时，核心工作是：

1. **定义协议合约** — 飞书 webhook 帧格式、消息卡片模板
2. **实现 session-key** — 从飞书消息提取 `{tenant_id, user_id, chat_id}` 映射到 Gong Session
3. **实现渠道适配器** — 飞书消息收发、卡片渲染、事件回调
4. **实现路由** — 根据消息类型分发到不同 Agent（编码 Agent、问答 Agent 等）
5. **运营面板** — 会话列表、Agent 状态、成本统计

Gong 这边不需要任何改动，Gateway 只消费 Session 公开 API。
