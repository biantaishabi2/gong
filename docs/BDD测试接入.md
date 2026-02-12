# Gong BDD 测试接入

## 概述

Gong 使用 `bdd_compiler`（bddc）编译器实现"文档即测试"。测试用例以 DSL 格式编写，由编译器验证指令合法性、生成 ExUnit 测试代码，最终通过 CI 门禁自动执行。

**不直接手写 ExUnit 测试。**

参考 Skill：`bdd-autochain`（`~/.claude/skills/bdd-autochain/`）

---

## 项目配置

```
project_root:     /home/wangbo/document/gong
registry_module:  Gong.BDD.InstructionRegistry
runtime_module:   Gong.BDD.Instructions.V1
docs_root:        docs/bdd
dsl_in:           docs/bdd
out:              test/bdd_generated
```

---

## 目录结构

```
gong/
├── lib/gong/bdd/
│   ├── instruction_registry.ex          # 主注册表入口
│   └── instruction_registries/
│       ├── common.ex                    # 通用指令（时间冻结、临时文件等）
│       ├── tools.ex                     # 工具指令（tool_read/write/edit/...）
│       ├── truncation.ex               # 截断系统指令
│       ├── agent.ex                    # Agent 集成指令
│       ├── hook.ex                     # Hook 系统指令
│       ├── compaction.ex               # 压缩系统指令
│       └── generated.ex               # bddc 自动生成（最低优先级）
├── test/support/bdd/
│   ├── instructions_v1.ex              # 运行时 dispatcher
│   └── fixtures.ex                     # 文件系统 fixture 工具
├── docs/bdd/
│   ├── read_action.dsl                 # J.3 的 20 个场景
│   ├── write_action.dsl                # J.4 的 9 个场景
│   ├── edit_action.dsl                 # J.1 的 26 个场景
│   ├── bash_action.dsl                 # J.2 的 21 个场景
│   ├── grep_action.dsl                 # J.5 的 11 个场景
│   ├── find_action.dsl                 # J.6 的 7 个场景
│   ├── ls_action.dsl                   # J.7 的 7 个场景
│   ├── truncation.dsl                  # J.8 的 14 个场景
│   ├── agent_integration.dsl           # J.9 的 26 个场景
│   ├── hook_system.dsl                 # J.10 的 18 个场景
│   └── compaction.dsl                  # J.12 的 8 个场景
├── test/bdd_generated/                 # 编译输出（不要手动编辑）
└── scripts/
    └── bdd_gate.sh                     # CI 门禁脚本
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

[SCENARIO: BDD-READ-004] TITLE: offset 参数分页 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="paged.txt" lines=100 line_length=20
WHEN tool_read path="paged.txt" offset=51
THEN assert_tool_success content_contains="51"

[SCENARIO: BDD-READ-005] TITLE: limit 参数分页 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="paged.txt" lines=100 line_length=20
WHEN tool_read path="paged.txt" limit=10
THEN assert_tool_success content_contains="offset" truncated=true

[SCENARIO: BDD-READ-006] TITLE: 行数截断 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="big.txt" lines=2500 line_length=20
WHEN tool_read path="big.txt"
THEN assert_tool_truncated truncated_by="lines" original_lines=2500

[SCENARIO: BDD-READ-007] TITLE: 符号链接跟随 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="real.txt" content="target content"
GIVEN create_symlink link="link.txt" target="real.txt"
WHEN tool_read path="link.txt"
THEN assert_tool_success content_contains="target content"

[SCENARIO: BDD-READ-008] TITLE: 权限不足 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="locked.txt" content="secret"
GIVEN set_file_permission path="locked.txt" mode="000"
WHEN tool_read path="locked.txt"
THEN assert_tool_error error_contains="EACCES"

[SCENARIO: BDD-READ-009] TITLE: 无效参数类型防护 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_read path=42
THEN assert_tool_error error_contains="参数"

[SCENARIO: BDD-READ-010] TITLE: tilde 路径展开 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="~/gong_test_tilde.txt" content="tilde test"
WHEN tool_read path="~/gong_test_tilde.txt"
THEN assert_tool_success content_contains="tilde test"
```

---

## 指令注册表

### 入口模块

```elixir
# lib/gong/bdd/instruction_registry.ex

defmodule Gong.BDD.InstructionRegistry do
  @moduledoc "Gong BDD 指令注册表入口"

  @spec fetch(atom(), :v1 | :v2) :: {:ok, map()} | :error
  def fetch(name, version \\ :v1) do
    Map.fetch(specs(version), name)
  end

  @spec specs(:v1 | :v2) :: map()
  def specs(:v1) do
    %{}
    |> merge_specs!(Gong.BDD.InstructionRegistries.Common.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Tools.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Truncation.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Agent.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Hook.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Compaction.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Generated.specs(:v1))
  end

  def specs(:v2), do: specs(:v1)

  defp merge_specs!(base, additions) do
    Map.merge(base, additions)
  end
end
```

### 领域注册表示例（Tools）

```elixir
# lib/gong/bdd/instruction_registries/tools.ex

defmodule Gong.BDD.InstructionRegistries.Tools do
  @moduledoc "工具 Action BDD 指令注册"

  def specs(:v1) do
    %{
      tool_read: %{
        name: :tool_read,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          offset: %{type: :int, required?: false, allowed: nil},
          limit: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      assert_tool_success: %{
        name: :assert_tool_success,
        kind: :then,
        args: %{
          content_contains: %{type: :string, required?: false, allowed: nil},
          truncated: %{type: :bool, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      assert_tool_error: %{
        name: :assert_tool_error,
        kind: :then,
        args: %{
          error_contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :error
      }

      # ... 其余工具指令同理
    }
  end

  def specs(:v2), do: %{}
end
```

---

## 运行时 Dispatcher

```elixir
# test/support/bdd/instructions_v1.ex

defmodule Gong.BDD.Instructions.V1 do
  @moduledoc "Gong BDD v1 指令运行时实现"

  import ExUnit.Assertions

  @type ctx :: map()
  @type meta :: map()

  # 编译期提取已实现的指令列表
  @supported_instructions (
    __ENV__.file
    |> File.read!()
    |> then(fn src ->
      Regex.scan(~r/\{\:(?:given|when|then),\s+\:([a-zA-Z0-9_]+)\}\s*->/, src,
        capture: :all_but_first
      )
    end)
    |> List.flatten()
    |> Enum.map(&String.to_atom/1)
    |> Enum.uniq()
    |> Enum.sort()
  )

  @spec capabilities() :: MapSet.t(atom())
  def capabilities, do: MapSet.new(@supported_instructions)

  @spec run!(ctx(), :given | :when | :then, atom(), map(), meta()) :: ctx()
  def run!(ctx, kind, name, args, meta \\ %{})

  # ── Common ──

  def run!(ctx, :given, :create_temp_dir, _args, _meta) do
    dir = Path.join(System.tmp_dir!(), "gong_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    # ExUnit on_exit 自动清理
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    Map.put(ctx, :workspace, dir)
  end

  def run!(ctx, :given, :create_temp_file, %{path: path, content: content}, _meta) do
    full = Path.join(ctx.workspace, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
    ctx
  end

  # ── Tools ──

  def run!(ctx, :when, :tool_read, args, _meta) do
    params = %{
      file_path: Path.join(ctx.workspace, args.path)
    }
    |> maybe_put(:offset, args[:offset])
    |> maybe_put(:limit, args[:limit])

    result = Jido.Action.run(Gong.Tools.Read, params)
    Map.put(ctx, :last_result, result)
  end

  # ── Assertions ──

  def run!(ctx, :then, :assert_tool_success, args, _meta) do
    assert {:ok, result} = ctx.last_result

    if cc = args[:content_contains] do
      assert result.content =~ cc,
        "期望内容包含 #{inspect(cc)}，实际：#{String.slice(result.content, 0, 200)}"
    end

    if args[:truncated] != nil do
      assert result.truncated == args.truncated
    end

    ctx
  end

  def run!(ctx, :then, :assert_tool_error, %{error_contains: expected}, _meta) do
    assert {:error, error} = ctx.last_result
    error_msg = if is_binary(error), do: error, else: inspect(error)
    assert error_msg =~ expected,
      "期望错误包含 #{inspect(expected)}，实际：#{error_msg}"
    ctx
  end

  # ── Helpers ──

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
```

---

## CI 门禁脚本

```bash
#!/usr/bin/env bash
# scripts/bdd_gate.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 查找 bdd_compiler
BIN="${BDD_COMPILER_BIN:-}"
if [ -z "$BIN" ]; then
  if [ -f "${ROOT_DIR}/tools/bdd_compiler/bdd_compiler" ]; then
    BIN="${ROOT_DIR}/tools/bdd_compiler/bdd_compiler"
  elif command -v bdd_compiler &>/dev/null; then
    BIN="bdd_compiler"
  elif command -v bddc &>/dev/null; then
    BIN="bddc"
  else
    echo "[bdd_gate] ERROR: bdd_compiler not found" >&2
    exit 1
  fi
fi

echo "[bdd_gate] using: ${BIN}"
echo "[bdd_gate] Step 1: compile + lint + runtime coverage"

${BIN} check \
  --project-root "${ROOT_DIR}" \
  --registry-module Gong.BDD.InstructionRegistry \
  --runtime-module Gong.BDD.Instructions.V1 \
  --docs-root docs \
  --in docs/bdd \
  --out test/bdd_generated

echo "[bdd_gate] Step 2: run generated tests"
cd "${ROOT_DIR}" && mix test test/bdd_generated/ --trace

echo "[bdd_gate] done ✓"
```

---

## 工作流程

### 新增工具时

以 read Action 为例：

```bash
# 1. 实现业务代码
#    → lib/gong/tools/read.ex

# 2. 写 DSL 场景
#    → docs/bdd/read_action.dsl

# 3. 补指令注册（如果用了新指令）
#    → lib/gong/bdd/instruction_registries/tools.ex

# 4. 补运行时实现
#    → test/support/bdd/instructions_v1.ex

# 5. 编译验证
bdd_compiler check \
  --project-root /home/wangbo/document/gong \
  --registry-module Gong.BDD.InstructionRegistry \
  --runtime-module Gong.BDD.Instructions.V1 \
  --docs-root docs \
  --in docs/bdd \
  --out test/bdd_generated

# 6. 跑测试
mix test test/bdd_generated/
```

### 一键串联（推荐）

```bash
bdd_compiler domain.autowire \
  --project-root /home/wangbo/document/gong \
  --module Gong.Tools.Read \
  --functions run/2 \
  --prefix tool \
  --kind when \
  --version v1 \
  --registry-module Gong.BDD.InstructionRegistry \
  --runtime-module Gong.BDD.Instructions.V1 \
  --in docs/bdd \
  --out test/bdd_generated \
  --strict true
```

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
