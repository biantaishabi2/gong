# Gong BDD 测试接入

## 概述

Gong 使用 `bddc` 编译器实现"文档即测试"。测试用例以 DSL 格式编写，由编译器验证指令合法性、生成 ExUnit 测试代码，最终通过 CI 门禁自动执行。

**不直接手写 ExUnit 测试。**

参考 Skill：`bdd-autochain`（`~/.claude/skills/bdd-autochain/`）

---

## 项目配置

所有配置收敛在项目根目录 `.bddc.toml`，bddc 命令自动读取，无需手动传参：

```toml
[global]
namespace = "Gong"
in = "docs/bdd"
out = "test/bdd_generated"
docs_root = "docs"
runtime_module = "Gong.BDD.Instructions.V1"
test_case = "ExUnit.Case"
module_prefix = "Gong.BDD.Generated"

[runtime.caps.sync]
out = "docs/bdd/_generated/runtime_caps_v1.exs"
```

---

## 目录结构

```
gong/
├── .bddc.toml                              # bddc 项目配置
├── lib/gong/bdd/
│   ├── instruction_registry.ex             # 主注册表入口
│   └── instruction_registries/
│       ├── common.ex                       # 通用指令（时间冻结、临时文件等）
│       ├── tools.ex                        # 工具指令（tool_read/write/edit/...）
│       ├── truncation.ex                   # 截断系统指令
│       ├── agent.ex                        # Agent 集成指令
│       ├── hook.ex                         # Hook 系统指令
│       ├── compaction.ex                   # 压缩系统指令
│       └── generated.ex                    # bddc 自动生成（GENERATED 区域）
├── test/support/bdd/
│   ├── instructions_v1.ex                  # 运行时 dispatcher
│   └── fixtures.ex                         # 文件系统 fixture 工具
├── docs/bdd/
│   ├── read_action.dsl                     # J.3 的 20 个场景
│   ├── write_action.dsl                    # J.4 的 9 个场景
│   ├── edit_action.dsl                     # J.1 的 26 个场景
│   ├── bash_action.dsl                     # J.2 的 21 个场景
│   ├── grep_action.dsl                     # J.5 的 11 个场景
│   ├── find_action.dsl                     # J.6 的 7 个场景
│   ├── ls_action.dsl                       # J.7 的 7 个场景
│   ├── truncation.dsl                      # J.8 的 14 个场景
│   ├── agent_integration.dsl              # J.9 的 26 个场景
│   ├── hook_system.dsl                     # J.10 的 18 个场景
│   └── compaction.dsl                      # J.12 的 8 个场景
├── test/bdd_generated/                     # 编译输出（不要手动编辑）
└── scripts/
    ├── bdd_gate.sh                         # BDD 门禁脚本
    └── pre_deploy_check.sh                 # 部署前全量门禁
```

---

## 指令设计

Gong 的 BDD 指令分为三个边界层：

### 边界分类

| boundary | 含义 | 示例 |
|----------|------|------|
| `:test_runtime` | 测试基础设施 | 时间冻结、临时目录创建 |
| `:external_io` | 文件系统 / 子进程 | tool_read、tool_bash |
| `:service` | Agent 层 / LLM 调用 | agent_chat、hook 注册 |

### 指令清单（按工具分）

#### Common（通用指令）

```elixir
# GIVEN
clock_freeze         # at: datetime — 冻结时间
create_temp_dir      # → 输出 $workspace 到 ctx
create_temp_file     # path: string, content: string — 在 workspace 下创建文件
create_binary_file   # path: string, bytes: int — 创建指定大小的二进制文件
create_symlink       # link: string, target: string — 创建符号链接
set_file_permission  # path: string, mode: string — 设置文件权限（如 "000"）
create_large_file    # path: string, lines: int, line_length: int — 创建大文件

# THEN
assert_file_exists   # path: string
assert_file_content  # path: string, expected: string
assert_file_not_modified  # path: string, original_hash: string
```

#### Tools（工具指令）

```elixir
# WHEN — 每个工具一条指令，参数映射 Action schema
tool_read   # path: string, offset?: int, limit?: int
tool_write  # path: string, content: string
tool_edit   # path: string, old_string: string, new_string: string, replace_all?: bool
tool_bash   # command: string, timeout?: int, cwd?: string
tool_grep   # pattern: string, path?: string, glob?: string, context?: int
tool_find   # pattern: string, path?: string, limit?: int
tool_ls     # path: string

# THEN — 工具结果断言
assert_tool_success        # content_contains?: string, truncated?: bool
assert_tool_error          # error_contains: string
assert_tool_truncated      # truncated_by?: string, original_lines?: int
assert_exit_code           # expected: int
assert_output_contains     # text: string
assert_output_not_contains # text: string
assert_result_field        # field: string, expected: string
```

#### Agent（Agent 集成指令）

```elixir
# GIVEN
configure_agent    # model: string, tools: string — 配置 Agent
register_hook      # module: string — 注册 Hook 模块
mock_llm_response  # response_type: string, content?: string — Mock LLM 响应

# WHEN
agent_chat         # prompt: string — 发送消息给 Agent
agent_stream       # prompt: string — 流式发送
agent_abort        # — 中断 Agent
trigger_compaction # — 触发压缩

# THEN
assert_agent_reply      # contains: string
assert_tool_was_called  # tool: string, times?: int
assert_tool_not_called  # tool: string
assert_hook_fired       # event: string
assert_hook_blocked     # reason_contains: string
assert_stream_events    # sequence: string — 如 "start,delta,end"
assert_no_crash         # — Agent 进程仍然存活
```

---

## DSL 示例

以 J.3 read Action 的前几个场景为例：

```
# read_action.dsl

[SCENARIO: BDD-READ-001] TITLE: 正常读取文件 TAGS: unit external_io
GIVEN create_temp_dir
LET workspace=$workspace
GIVEN create_temp_file path="test.txt" content="line1\nline2\nline3\n"
WHEN tool_read path="test.txt"
THEN assert_tool_success content_contains="line1" truncated=false

[SCENARIO: BDD-READ-002] TITLE: 文件不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_read path="nonexistent.txt"
THEN assert_tool_error error_contains="ENOENT"

[SCENARIO: BDD-READ-003] TITLE: 空文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="empty.txt" content=""
WHEN tool_read path="empty.txt"
THEN assert_tool_success truncated=false
```

---

## CI 门禁

### bdd_gate.sh

有了 `.bddc.toml`，门禁脚本无需传参：

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bddc check                              # 自动读取 .bddc.toml
mix compile --warnings-as-errors
mix test test/bdd_generated/ --trace
```

### pre_deploy_check.sh

全量门禁（BDD + 编译 + 测试），支持 `--bdd-only` / `--skip-bdd` 等开关。

---

## 工作流程

### 新增工具时

```bash
# 1. 实现业务代码
#    → lib/gong/tools/xxx.ex

# 2. 写 DSL 场景
#    → docs/bdd/xxx_action.dsl

# 3. 补指令注册（如果用了新指令）
#    可用 bddc registry.scaffold 生成草稿
#    → lib/gong/bdd/instruction_registries/tools.ex

# 4. 补运行时实现
#    → test/support/bdd/instructions_v1.ex

# 5. 一键验证
bddc check
mix test test/bdd_generated/
```

### 一键串联（推荐）

```bash
bddc domain.autowire \
  --module Gong.Tools.Read \
  --functions run/2 \
  --prefix tool \
  --kind when \
  --version v1 \
  --strict true
```

配置参数（namespace、in、out、runtime_module 等）由 `.bddc.toml` 自动提供。

---

## 强约束

1. **新指令必须两层都补**：注册表（编译期 schema）+ 运行时（`run!/5` 分发）
2. **只测可观测行为**：DSL 断言的是工具返回值，不是内部实现细节
3. **确定性数据**：GIVEN 准备的文件内容、路径都是确定的，禁止隐式随机
4. **不直接写 ExUnit**：`test/bdd_generated/` 目录由编译器生成，不要手动编辑
5. **DSL 场景对应 architecture.md J 节**：每个 DSL 文件的场景 ID 对应架构文档的测试编号

---

## 场景 ID 映射

| DSL 文件 | architecture.md | 场景数 |
|----------|-----------------|--------|
| `read_action.dsl` | J.3 | 20 |
| `write_action.dsl` | J.4 | 9 |
| `edit_action.dsl` | J.1 | 26 |
| `bash_action.dsl` | J.2 | 21 |
| `grep_action.dsl` | J.5 | 11 |
| `find_action.dsl` | J.6 | 7 |
| `ls_action.dsl` | J.7 | 7 |
| `truncation.dsl` | J.8 | 14 |
| `agent_integration.dsl` | J.9 | 26 |
| `hook_system.dsl` | J.10 | 18 |
| `compaction.dsl` | J.12 | 8 |
| **合计** | | **167** |
