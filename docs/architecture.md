# 编码 Agent 完整架构参考（基于 Pi 实现分析）

本文档基于对 [pi-mono](https://github.com/badlogic/pi-mono) 项目的深度代码分析，记录构建一个生产级编码 Agent 所需的完整架构和工程细节。

---

## 一、整体架构

```
┌────────────────────────────────────────────────────┐
│                   应用层                            │
│  CLI (Interactive / Print / RPC)                   │
└──────────────────────┬─────────────────────────────┘
                       │
┌──────────────────────▼─────────────────────────────┐
│                 Agent Session                       │
│  会话生命周期 / 自动压缩 / 自动重试 / 模型切换       │
└──────────────────────┬─────────────────────────────┘
                       │
┌──────────────────────▼─────────────────────────────┐
│                  Agent Loop                         │
│  双层循环 / 中断机制 / 工具调度 / 事件流             │
└───────┬──────────────────────────────┬─────────────┘
        │                              │
┌───────▼───────────┐    ┌─────────────▼─────────────┐
│    工具系统        │    │     LLM Provider 层       │
│  read/write/edit  │    │  统一接口 + Adapter 适配   │
│  bash/grep/find   │    │  Anthropic / OpenAI / ...  │
└───────────────────┘    └───────────────────────────┘
        │                              │
┌───────▼──────────────────────────────▼─────────────┐
│                   存储层                            │
│  会话持久化 / 索引 / 上下文压缩                      │
└────────────────────────────────────────────────────┘
```

---

## 二、Agent Loop

### 2.1 双层循环设计

Agent Loop 不是简单的 "调 LLM → 执行工具 → 再调 LLM" 循环，而是一个支持中断和续接的双层结构：

```
外层循环 (处理 follow-up 消息)
│
└─ while true:
    │
    ├─ 内层循环 (处理 tool calls + steering 消息)
    │  │
    │  └─ while hasToolCalls || pendingMessages:
    │       ├─ 注入待发消息到上下文
    │       ├─ [可选] transformContext (裁剪/压缩)
    │       ├─ convertToLlm (格式转换)
    │       ├─ 流式调用 LLM
    │       ├─ 解析 tool calls
    │       ├─ 顺序执行每个 tool call:
    │       │    ├─ 执行工具
    │       │    ├─ 检查 steering 消息 ← 关键：每个工具后都检查
    │       │    └─ 如有中断 → 跳过剩余工具，注入中断消息
    │       └─ 将工具结果加入上下文
    │
    ├─ 检查 follow-up 消息
    │   ├─ 有 → 注入为待发消息，continue 外层循环
    │   └─ 无 → break 退出
    │
    └─ 发出 agent_end 事件
```

### 2.2 三种消息注入机制

| 机制 | 触发时机 | 用途 |
|------|---------|------|
| **prompt** | Agent 空闲时 | 正常用户输入 |
| **steering** | 工具执行期间 | 用户中断当前操作 |
| **follow-up** | Agent 完成后 | 自动追加后续任务 |

steering 消息到来时，剩余未执行的工具会被标记为跳过，并返回错误结果给 LLM：
```
"Skipped due to queued user message"
```

### 2.3 停止条件

1. LLM 返回 stopReason 为 error 或 aborted → 立即结束
2. 无 tool calls 且无待发消息 → 退出内层循环
3. 无 follow-up 消息 → 退出外层循环

### 2.4 流式消息管理

LLM 响应是流式到达的，需要在上下文中维护一个"占位消息"：

```
message_start → 在 context.messages 末尾添加 partial message
message_update → 替换末尾的 partial message
message_end → 替换为 final message
```

如果流中途被中断（abort），需要判断 partial message 是否有实质内容：
- 有内容 → 保存到历史
- 全空 → 丢弃，抛出 aborted 错误

### 2.5 事件系统

Agent Loop 通过事件流与外部通信：

```
agent_start / agent_end
turn_start / turn_end
message_start / message_update / message_end
tool_execution_start / tool_execution_update / tool_execution_end
```

所有消费者通过 subscribe 订阅事件，支持实时 UI 更新、日志记录、持久化等。

---

## 三、工具系统

### 3.1 工具列表

| 工具 | 功能 | 截断策略 |
|------|------|---------|
| read | 读文件（文本 + 图片） | head（保留开头） |
| write | 创建/覆写文件 | 无 |
| edit | 精确文本替换 | 无 |
| bash | 执行 shell 命令 | tail（保留末尾） |
| grep | 搜索文件内容 | head + line（单行截断） |
| find | 搜索文件名 | head |
| ls | 列出目录 | head |

### 3.2 edit —— 最复杂的工具

#### 两层匹配策略

```
输入: oldText, newText, filePath
        │
        ▼
   读取文件内容
        │
        ▼
   BOM 检测并移除（保存，最后恢复）
        │
        ▼
   行尾正规化（CRLF → LF，记录原始格式）
        │
        ▼
   精确匹配 indexOf(oldText)
        │
   ┌────┴────┐
  成功      失败
   │         │
   │         ▼
   │    模糊匹配（5 步规范化）
   │         │
   │    ┌────┴────┐
   │   成功      失败
   │    │         │
   │    │         ▼
   │    │    返回错误给 LLM
   │    │
   ▼    ▼
  唯一性检查（出现次数必须 = 1）
        │
   ┌────┴────┐
  唯一      多次
   │         │
   │         ▼
   │    返回 "Found N occurrences, provide more context"
   │
   ▼
  执行替换 → 恢复行尾 → 恢复 BOM → 写入文件
        │
        ▼
  生成 unified diff（返回给用户看）
```

#### 模糊匹配的 5 步规范化

1. **去尾部空格**：每行末尾的空格移除
2. **弯引号 → ASCII**：`'` `'` `"` `"` → `'` `"`（U+2018-U+201F）
3. **Unicode 破折号 → 连字符**：en-dash, em-dash 等 7 种 → `-`（U+2010-U+2015, U+2212）
4. **Unicode 空格 → 普通空格**：NBSP, em-space 等 → ` `（U+00A0, U+2002-U+200A, U+3000 等）
5. **NFD 规范化**（macOS 文件系统）

这些规范化是必要的，因为 LLM 生成的文本经常自动替换这些字符。

#### 错误消息设计

错误消息必须对 LLM 有操作指导意义：

| 场景 | 错误消息 |
|------|---------|
| 文件不存在 | `"File not found: {path}"` |
| 匹配失败 | `"Could not find the exact text in {path}. The old text must match exactly including all whitespace and newlines."` |
| 多次出现 | `"Found {N} occurrences of the text in {path}. The text must be unique. Please provide more context to make it unique."` |
| 无变化 | `"No changes made to {path}. The replacement produced identical content."` |

### 3.3 bash —— 最工程化的工具

#### 输出管理：滚动缓冲区

```
命令输出流
    │
    ▼
内存缓冲区 (chunks[], 最大 100KB 滚动窗口)
    │
    ├─ 总字节数 < 50KB → 仅内存
    │
    └─ 总字节数 ≥ 50KB → 同时写临时文件
                              │
                              ▼
                         /tmp/pi-bash-{random}.log
```

- 内存中始终保留最近 100KB（丢弃最旧的 chunk）
- 超过 50KB 时开始写临时文件（完整保留）
- 最终返回 tail 截断（最后 2000 行或 50KB）

#### 进程管理

- 使用 `spawn()` 创建子进程
- 超时通过 `setTimeout` + `killProcessTree()` 实现
- abort 信号通过 `AbortSignal` 传递，触发 `killProcessTree()`
- `killProcessTree` 递归杀死整个进程树，防止僵尸进程

#### 错误消息格式

```
成功 + 无截断:     "output"
成功 + 截断:       "output\n[Showing lines 1950-2000 of 5000. Full output: /tmp/xxx.log]"
失败:             "output\n\nCommand exited with code 127"
超时:             "output\n\nCommand timed out after 30 seconds"
中止:             "Command aborted"
```

#### 可扩展设计

```go
type BashOperations interface {
    Exec(command, cwd string, opts ExecOptions) (string, error)
}
```

可替换为 SSH 远程执行、Docker 容器执行等。

### 3.4 read —— 边界情况最多的工具

#### 双模式处理

```
检测文件 MIME 类型
    │
    ├─ 图片 (jpg/png/gif/webp)
    │    ├─ 读取为 base64
    │    ├─ 自动缩放到 2000×2000
    │    └─ 返回 [text描述, image数据]
    │
    └─ 文本
         ├─ 应用 offset + limit 分页
         ├─ head 截断 (2000 行或 50KB)
         └─ 返回文本 + 截断提示
```

#### 分页提示

```
截断 (行数限制):  "[Showing lines 1-2000 of 5000. Use offset=2001 to continue.]"
截断 (字节限制):  "[Showing lines 1-1500 of 5000 (50KB limit). Use offset=1501 to continue.]"
首行超大:        "[Line 42 is 120KB, exceeds 50KB limit. Use bash: sed -n '42p' {path} | head -c 50000]"
还有更多:        "[1000 more lines in file. Use offset=51 to continue.]"
```

#### macOS 路径兼容

文件找不到时，依次尝试 5 种路径变体：

1. 原始路径
2. AM/PM 窄空格变体（U+202F 替代普通空格）
3. NFD 规范化变体
4. 弯引号变体（U+2019 替代 U+0027）
5. NFD + 弯引号组合

### 3.5 grep —— ripgrep 集成

#### 调用方式

```bash
rg --json --line-number --color=never --hidden [--ignore-case] [--fixed-strings] [--glob pattern] <pattern> <path>
```

使用 `--json` 输出，每行一个 JSON 对象，流式解析。

#### 三层截断

1. **匹配数限制**：默认 100 个，达到后杀死 ripgrep 进程
2. **单行截断**：每行最多 500 字符，超出加 `... [truncated]`
3. **总字节截断**：输出最多 50KB

#### 文件缓存

同一文件被多个匹配引用时，缓存文件内容避免重复读取。

### 3.6 截断系统

三种截断函数，返回统一的元数据结构：

```go
type TruncationResult struct {
    Content              string
    Truncated            bool
    TruncatedBy          string  // "lines" | "bytes" | ""
    TotalLines           int
    TotalBytes           int
    OutputLines          int
    OutputBytes          int
    LastLinePartial      bool    // 仅 tail
    FirstLineExceedsLimit bool   // 仅 head
    MaxLines             int
    MaxBytes             int
}
```

| 函数 | 保留方向 | 用于 | 部分行处理 |
|------|---------|------|-----------|
| truncateHead | 开头 | read, grep | 不返回部分行 |
| truncateTail | 末尾 | bash | 最后一行可能被截断 |
| truncateLine | 单行 | grep 行 | 超过 500 字符截断 |

**UTF-8 边界感知**：tail 截断时需要找到有效的 UTF-8 字符边界，跳过续字节（10xxxxxx）。

### 3.7 所有工具的共性设计

- **Abort 信号**：所有工具在多个检查点监听 AbortSignal，及时清理资源
- **可插拔操作接口**：每个工具定义 Operations 接口，可替换底层实现
- **错误即指导**：错误消息告诉 LLM 怎么修正，而不只是说"失败了"
- **流式进度**：长时间工具（bash）通过 onUpdate 回调推送中间状态

---

## 三（续）、工具详细设计：Jido Action 实现指南

基于 Pi 源码的逐行分析，以下是每个工具作为 Jido Action 的完整设计规格和测试场景。

### A. edit —— 最复杂的工具

#### 完整执行流水线（10 步）

```
输入: path, oldText, newText
    │
    ▼ ① 路径解析（~展开、@前缀去除、Unicode空格正规化、相对→绝对）
    ▼ ② 文件存在性检查（R_OK | W_OK）
    ▼ ③ 读取文件为 UTF-8 字符串
    ▼ ④ BOM 分离（检测并去除 \uFEFF，保存待恢复）
    ▼ ⑤ 行尾检测（CRLF 还是 LF，看第一个换行符）
    ▼ ⑥ 三个字符串统一正规化为 LF（content、oldText、newText）
    ▼ ⑦ 两层匹配（精确 → 模糊）
    ▼ ⑧ 唯一性检查（在模糊正规化空间计数，必须 = 1）
    ▼ ⑨ 执行替换 → 恢复行尾 → 恢复 BOM → 写入文件
    ▼ ⑩ 生成 unified diff（4 行上下文，返回给 UI）
```

#### 模糊匹配的 5 类规范化

| # | 类别 | 转换规则 | 原因 |
|---|------|---------|------|
| 1 | 去尾部空格 | 每行 `trimEnd()` | LLM 经常丢失尾部空格 |
| 2 | 弯单引号 → ASCII | `\u2018\u2019\u201A\u201B` → `'` | LLM 自动替换引号 |
| 3 | 弯双引号 → ASCII | `\u201C\u201D\u201E\u201F` → `"` | 同上 |
| 4 | Unicode 破折号 → 连字符 | `\u2010-\u2015, \u2212` → `-` | en-dash/em-dash 混用 |
| 5 | Unicode 空格 → 普通空格 | `\u00A0, \u2002-\u200A, \u202F, \u205F, \u3000` → ` ` | NBSP/全角空格等 |

#### BOM 处理

```elixir
# 分离 BOM
{bom, text} = case content do
  <<0xFEFF::utf8, rest::binary>> -> {<<0xFEFF::utf8>>, rest}
  _ -> {"", content}
end

# 所有匹配和替换在 text（无 BOM）上进行
# 写回时前置 bom
File.write!(path, bom <> restored_content)
```

#### CRLF 处理

```elixir
# 检测：看第一个换行符
original_ending = if String.contains?(content, "\r\n"), do: :crlf, else: :lf

# 正规化为 LF
normalized = content |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")

# 替换后恢复
restored = case original_ending do
  :crlf -> String.replace(result, "\n", "\r\n")
  :lf -> result
end
```

#### 唯一性检查关键点

计数**始终在模糊正规化空间**进行，即使初始匹配是精确的。这样 `"hello world   "` 和 `"hello world"` 被视为同一匹配。

```elixir
fuzzy_content = normalize_fuzzy(content)
fuzzy_old = normalize_fuzzy(old_text)
count = length(String.split(fuzzy_content, fuzzy_old)) - 1
if count > 1, do: {:error, "Found #{count} occurrences..."}
```

#### 错误消息（5 种）

| 场景 | 消息 |
|------|------|
| 文件不存在 | `"File not found: {path}"` |
| 匹配失败 | `"Could not find the exact text in {path}. The old text must match exactly including all whitespace and newlines."` |
| 多次出现 | `"Found {N} occurrences of the text in {path}. The text must be unique. Please provide more context to make it unique."` |
| 无变化 | `"No changes made to {path}. The replacement produced identical content."` |
| 被中断 | `"Operation aborted"` |

#### Diff 生成

4 行上下文的 unified diff。返回 `{diff, first_changed_line}`，`first_changed_line` 用于编辑器跳转。格式：

```
       ...
  10 context before
  11 context before
- 12 old removed line
+ 12 new added line
  13 context after
  14 context after
       ...
```

#### 测试场景（16 个）

**基础（3 个）：**

| 测试 | 场景 |
|------|------|
| 基本替换 | "Hello, world!" 中 "world" → "testing"，验证 "Successfully replaced" |
| 文本不存在 | 搜索 "nonexistent"，验证错误消息 |
| 多次出现 | "foo foo foo" 中搜 "foo"，验证 "Found 3 occurrences" |

**模糊匹配（8 个）：**

| 测试 | 场景 |
|------|------|
| 尾部空格 | 文件有 `"line one   \n"`，oldText 无尾部空格 |
| 弯单引号 | 文件有 `\u2018hello\u2019`，oldText 用 `'hello'` |
| 弯双引号 | 文件有 `\u201CHello\u201D`，oldText 用 `"Hello"` |
| Unicode 破折号 | 文件有 en-dash `\u2013` 和 em-dash `\u2014`，oldText 用 `-` |
| 非断行空格 | 文件有 `\u00A0`（NBSP），oldText 用普通空格 |
| 精确优先 | 文件是纯 ASCII，验证精确匹配被使用（无规范化副作用） |
| 模糊也找不到 | 内容完全不同，验证错误 |
| 模糊后重复 | 两行仅尾部空格不同，模糊化后相同 → "Found 2 occurrences" |

**CRLF/BOM（5 个）：**

| 测试 | 场景 |
|------|------|
| LF 的 oldText vs CRLF 文件 | 跨平台行尾不匹配，应匹配成功 |
| CRLF 保留 | 编辑后文件仍为 `\r\n` |
| LF 保留 | 编辑后文件仍为 `\n`（不会意外注入 `\r\n`） |
| 混合行尾重复检测 | `"hello\r\nworld"` 和 `"hello\nworld"` 正规化后相同 → 2 次出现 |
| BOM + CRLF 保留 | `\uFEFF` 开头 + CRLF 文件，编辑后两者都保留 |

---

### B. bash —— 最工程化的工具

#### 执行架构

```
LLM 调用 bash(command, timeout)
    │
    ▼ 可选：前置 commandPrefix（环境变量设置等）
    ▼ spawn(shell, ["-c", command], detached: true)
    │
    ├─ stdout ──┐
    └─ stderr ──┤
                ▼
         handleData 回调
              │
    ┌─────────┼──────────────┐
    │         │              │
    ▼         ▼              ▼
  内存缓冲区   临时文件        onUpdate 回调
  (≤100KB     (>50KB 时创建    (流式推送
   滚动窗口)   完整保留)        截断后的尾部)
              │
              ▼
         进程结束
              │
              ▼
    truncateTail(2000行/50KB)
              │
              ▼
         附加截断提示
```

#### 滚动缓冲区实现

```elixir
# 状态
chunks = []        # Buffer 列表
chunks_bytes = 0   # 当前缓冲区字节数
total_bytes = 0    # 总输出字节数
temp_file = nil    # 临时文件路径

def handle_data(data) do
  total_bytes += byte_size(data)

  # 超过 50KB 开始写临时文件（首次时回填所有已有 chunks）
  if total_bytes > 50_000 and is_nil(temp_file) do
    temp_file = create_temp_file()
    Enum.each(chunks, &write_to_file(temp_file, &1))
  end

  if temp_file, do: write_to_file(temp_file, data)

  # 滚动窗口：保留最近 100KB
  chunks = chunks ++ [data]
  chunks_bytes += byte_size(data)
  while chunks_bytes > 100_000 and length(chunks) > 1 do
    {removed, chunks} = List.pop_at(chunks, 0)
    chunks_bytes -= byte_size(removed)
  end
end
```

#### 进程树杀死

```elixir
# Unix: 用进程组信号（需要 detached: true 创建进程组）
def kill_process_tree(pid) do
  # 负 PID = 发送信号给整个进程组
  System.cmd("kill", ["-9", "-#{pid}"])
rescue
  # 回退：只杀单个进程
  System.cmd("kill", ["-9", "#{pid}"])
rescue
  :ok  # 进程已死
end
```

#### 超时处理

- 用户指定的 timeout 单位是**秒**
- 到时间后 `kill_process_tree(pid)` 杀掉整个进程树
- 错误消息包含已收集的输出：`"[output]\n\nCommand timed out after {N} seconds"`

#### 中断处理

- AbortSignal 触发时同样 `kill_process_tree`
- 在调用开始前检查是否已经 aborted
- 错误消息：`"[output]\n\nCommand aborted"`

#### 输出格式

```
成功 + 无截断:     "output"
成功 + 截断:       "output\n[Showing lines 501-2500 of 2500. Full output: /tmp/xxx.log]"
失败:             "output\n\nCommand exited with code 127"
超时:             "output\n\nCommand timed out after 30 seconds"
中止:             "Command aborted"
```

#### 测试场景（8 个）

| 测试 | 场景 |
|------|------|
| 简单命令 | `echo hello`，验证输出文本、无截断详情 |
| 命令错误 | `exit 1`，验证 "code 1" 错误 |
| 超时 | `sleep 5` + timeout=1，验证 "timed out" |
| 不存在的 cwd | `/this/directory/does/not/exist`，验证错误 |
| spawn 失败 | 不存在的 shell 路径，验证 ENOENT 错误 |
| 命令前缀 | `commandPrefix: "export TEST_VAR=hello"`，运行 `echo $TEST_VAR` |
| 前缀+命令输出 | prefix 和 command 都有输出，两者都可见 |
| 无前缀 | 空选项，正常执行 |

---

### C. read —— 边界情况最多的工具

#### 执行流水线

```
输入: path, offset?, limit?
    │
    ▼ resolveReadPath（5 层 macOS 路径回退）
    ▼ 检测 MIME 类型（magic bytes，读文件头 4100 字节）
    │
    ├─ 图片 (jpeg/png/gif/webp)
    │    ├─ 读取为 base64
    │    ├─ 自动缩放到 2000×2000，≤4.5MB
    │    │   (尝试 PNG/JPEG 取较小；逐步降低质量 85→70→55→40)
    │    │   (仍超限则逐步缩小尺寸 75%→50%→35%→25%)
    │    └─ 返回 [text描述 + 缩放说明, image数据]
    │
    └─ 文本
         ├─ 全文读取 → 按 \n 分行
         ├─ 应用 offset（1-indexed，转为 0-indexed）
         │   offset > 总行数 → 报错 "Offset N is beyond end of file (M lines total)"
         ├─ 应用用户 limit
         └─ truncateHead (2000 行 / 50KB)
```

#### macOS 路径回退（5 步）

| 步骤 | 变体 | 原因 |
|------|------|------|
| 1 | 原始路径 | 正常情况 |
| 2 | AM/PM 窄空格 | macOS 截图文件名用 U+202F 代替普通空格 |
| 3 | NFD 规范化 | macOS APFS 用 NFD（分解形式）存文件名 |
| 4 | 弯引号变体 | macOS 法语截图 "Capture d'écran" 用 U+2019 |
| 5 | NFD + 弯引号组合 | 上述两者组合 |

每步只有前一步找不到文件时才尝试。

#### 截断提示（4 种）

```
首行超大:     "[Line N is SIZE, exceeds 50.0KB limit. Use bash: sed -n 'Np' PATH | head -c 51200]"
行数截断:     "[Showing lines 1-2000 of 5000. Use offset=2001 to continue.]"
字节截断:     "[Showing lines 1-1500 of 5000 (50.0KB limit). Use offset=1501 to continue.]"
用户 limit:  "[1000 more lines in file. Use offset=51 to continue.]"
```

#### 测试场景（13 个）

| 测试 | 场景 |
|------|------|
| 正常读取 | 3 行文件，无截断，details 为 undefined |
| 文件不存在 | 期望 ENOENT 错误 |
| 行数截断 | 2500 行文件 → 截断到 2000 行，验证提示消息 |
| 字节截断 | 500 行 × 200 字符 > 50KB，验证字节截断消息 |
| offset 参数 | 100 行文件从第 51 行开始读 |
| limit 参数 | 100 行文件只读 10 行，验证 "[90 more lines...]" |
| offset + limit | offset=41, limit=20 → 读 41-60 行 |
| offset 越界 | offset=100，文件只有 3 行，验证错误 |
| 截断详情元数据 | 验证 `truncated=true, truncatedBy="lines", totalLines=2500` |
| 图片 MIME 检测 | PNG 内容存为 `.txt` 扩展名 → 仍识别为 image/png |
| 非图片但图片扩展名 | 文本内容存为 `.png` → 返回文本，无 ImageContent |

---

### D. write —— 最简单的工具

#### 执行流水线

```
输入: path, content
    │
    ▼ resolveToCwd（路径解析，无 macOS 回退）
    ▼ mkdir -p（递归创建所有父目录）
    ▼ File.write!（UTF-8 编码，覆写模式）
    ▼ 返回 "Successfully wrote {length} bytes to {path}"
```

#### 行为特征

- 文件不存在 → 创建
- 文件已存在 → 覆写（无确认）
- 父目录不存在 → 自动递归创建
- 始终 UTF-8 编码
- 无文件大小检查
- 无备份/回滚机制

#### 测试场景（2 个）

| 测试 | 场景 |
|------|------|
| 基本写入 | 写入内容，验证 "Successfully wrote" 消息 |
| 创建父目录 | 写入 `nested/dir/test.txt`，验证递归创建 |

---

### E. grep —— ripgrep 集成

#### 执行架构：两阶段

```
阶段 1: ripgrep 发现匹配
    rg --json --line-number --color=never --hidden [flags] pattern path
    │
    ▼ 流式 JSON 解析（每行一个 JSON 对象）
    ▼ 只处理 type="match" 事件，提取 {filePath, lineNumber}
    ▼ 达到 limit（默认 100）后杀死 rg 进程

阶段 2: 重新读取文件格式化输出
    │
    ▼ 文件缓存（同一文件多个匹配只读一次）
    ▼ 添加上下文行（context 参数）
    ▼ 单行截断（>500 字符加 "... [truncated]"）
    ▼ truncateHead（仅字节限制 50KB，无行数限制）
    ▼ 附加提示通知
```

#### 参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| pattern | string | 必填 | 正则或字面量 |
| path | string? | cwd | 搜索目录或文件 |
| glob | string? | 无 | 文件过滤，如 `*.ts` |
| ignoreCase | bool? | false | 大小写不敏感 |
| literal | bool? | false | 字面量匹配（非正则） |
| context | number? | 0 | 匹配前后上下文行数 |
| limit | number? | 100 | 最大匹配数 |

#### 三层截断

1. **匹配数限制**：达到 limit 后杀死 rg 进程
2. **单行截断**：每行 > 500 字符 → `slice(0, 500) + "... [truncated]"`
3. **总字节截断**：输出 > 50KB → truncateHead

#### 输出格式

```
# 匹配行用 : 分隔
src/main.ts:42: const result = processData(input);
# 上下文行用 - 分隔
src/main.ts-41- function processData(input: any) {
src/main.ts:42: const result = processData(input);
src/main.ts-43-   return result;
```

#### 提示通知（3 种）

```
"100 matches limit reached. Use limit=200 for more, or refine pattern"
"50.0KB limit reached"
"Some lines truncated to 500 chars. Use read tool to see full lines"
```

#### 测试场景（2 个）

| 测试 | 场景 |
|------|------|
| 单文件搜索 | 搜索单个文件，验证输出含 `filename:line: content` 格式 |
| limit + context | limit=1 + context=1，验证只 1 个匹配 + 上下文行 + 限制通知 |

---

### F. find —— fd 集成

#### 执行流程

```
输入: pattern, path?, limit?
    │
    ▼ 检查 fd 可用性（本地 → PATH → 自动下载）
    ▼ 收集所有 .gitignore 文件（含嵌套的）
    ▼ fd --glob --color=never --hidden --max-results N [--ignore-file ...] pattern path
    ▼ 路径相对化（去掉搜索目录前缀）
    ▼ 保留目录尾部 /
    ▼ truncateHead（仅字节限制 50KB）
```

#### 关键特性

- `--hidden` 始终开启 → 搜索 dotfiles
- 自动尊重 `.gitignore`（通过 `--ignore-file` 传递）
- 使用 `spawnSync`（同步执行，不流式）
- `--max-results` 由 fd 内置限制结果数

#### 测试场景（2 个）

| 测试 | 场景 |
|------|------|
| 含隐藏文件 | 创建 `.secret/hidden.txt` 和 `visible.txt`，两者都出现 |
| 尊重 .gitignore | 创建 `.gitignore` 含 `ignored.txt`，验证被排除 |

---

### G. ls —— 纯文件系统实现

#### 执行流程

```
输入: path?, limit?
    │
    ▼ resolveToCwd（默认当前目录）
    ▼ 验证路径存在
    ▼ 验证是目录（不是文件）
    ▼ readdirSync 读取条目
    ▼ 按字母排序（大小写不敏感）
    ▼ 对每个条目 stat → 目录加 / 后缀
    ▼ 无法 stat 的条目静默跳过（如断开的符号链接）
    ▼ truncateHead（仅字节限制 50KB）
```

#### 特性

- 只列当前目录，无递归选项（深度=1）
- 含 dotfiles（readdirSync 默认行为）
- 空目录返回 `"(empty directory)"`
- 默认限制 500 条目

#### 测试场景（1 个）

| 测试 | 场景 |
|------|------|
| dotfiles 和目录 | 创建 `.hidden-file` 和 `.hidden-dir/`，验证都出现且目录有 `/` 后缀 |

---

### H. 截断系统设计

#### 三种策略总览

| 策略 | 保留方向 | 用于 | 默认限制 |
|------|---------|------|---------|
| `truncate_head` | 开头 | read, grep, find, ls | 2000 行 / 50KB |
| `truncate_tail` | 末尾 | bash | 2000 行 / 50KB |
| `truncate_line` | 单行 | grep 单行 | 500 字符 |

注意：grep/find/ls 禁用行数限制（设为无穷大），只用字节限制。因为它们有自己的匹配数/结果数限制。

#### truncate_head 算法

```elixir
def truncate_head(content, max_lines \\ 2000, max_bytes \\ 50_000) do
  lines = String.split(content, "\n")

  # 快速检查
  if length(lines) <= max_lines and byte_size(content) <= max_bytes do
    %{content: content, truncated: false, ...}
  end

  # 特殊：首行就超字节限制
  if byte_size(hd(lines)) > max_bytes do
    %{content: "", truncated: true, first_line_exceeds_limit: true, ...}
  end

  # 逐行累加
  {output, _} = Enum.reduce_while(lines, {[], 0}, fn line, {acc, bytes} ->
    line_bytes = byte_size(line) + if(acc == [], do: 0, else: 1)  # +1 for \n
    if bytes + line_bytes > max_bytes or length(acc) >= max_lines do
      {:halt, {acc, bytes}}
    else
      {:cont, {acc ++ [line], bytes + line_bytes}}
    end
  end)

  %{content: Enum.join(output, "\n"), truncated: true, ...}
end
```

#### truncate_tail 算法

```elixir
def truncate_tail(content, max_lines \\ 2000, max_bytes \\ 50_000) do
  lines = String.split(content, "\n")

  # 从末尾往回收集
  {output, _} = lines
  |> Enum.reverse()
  |> Enum.reduce_while({[], 0}, fn line, {acc, bytes} ->
    line_bytes = byte_size(line) + if(acc == [], do: 0, else: 1)
    cond do
      bytes + line_bytes > max_bytes and acc == [] ->
        # 特殊：末行超限，取尾部字节（UTF-8 边界安全）
        {:halt, {[truncate_bytes_from_end(line, max_bytes)], max_bytes}}
      bytes + line_bytes > max_bytes ->
        {:halt, {acc, bytes}}
      length(acc) >= max_lines ->
        {:halt, {acc, bytes}}
      true ->
        {:cont, {[line | acc], bytes + line_bytes}}
    end
  end)

  %{content: Enum.join(output, "\n"), truncated: true, last_line_partial: ..., ...}
end
```

#### UTF-8 边界安全截断

```elixir
def truncate_bytes_from_end(string, max_bytes) do
  bytes = :binary.bin_to_list(string)
  start = length(bytes) - max_bytes

  # 跳过 UTF-8 续字节（10xxxxxx）
  start = advance_to_char_boundary(bytes, start)

  string
  |> :binary.part(start, length(bytes) - start)
end

defp advance_to_char_boundary(bytes, pos) do
  byte = Enum.at(bytes, pos)
  # 续字节的高 2 位是 10
  if (byte &&& 0xC0) == 0x80 do
    advance_to_char_boundary(bytes, pos + 1)  # 向前跳
  else
    pos
  end
end
```

**关键**：截断点如果落在多字节字符中间，向**前**（向文件末尾方向）移动到下一个有效字符起始字节。结果可能少于 max_bytes 几个字节，但保证 UTF-8 完整。

#### 返回值结构

```elixir
%TruncationResult{
  content: String.t(),
  truncated: boolean(),
  truncated_by: :lines | :bytes | nil,
  total_lines: integer(),
  total_bytes: integer(),
  output_lines: integer(),
  output_bytes: integer(),
  last_line_partial: boolean(),        # 仅 tail：末行被字节截断
  first_line_exceeds_limit: boolean(), # 仅 head：首行就超限
  max_lines: integer(),
  max_bytes: integer()
}
```

---

### I. 所有工具的 Jido Action 映射

```elixir
# mix.exs 依赖
{:jido, "~> 2.0.0-rc.4"},
{:jido_ai, "~> x.x"},
{:req_llm, "~> 1.5"}

# Action 模块列表
defmodule CodingAgent.Tools do
  @tools [
    CodingAgent.Tools.Read,
    CodingAgent.Tools.Write,
    CodingAgent.Tools.Edit,
    CodingAgent.Tools.Bash,
    CodingAgent.Tools.Grep,
    CodingAgent.Tools.Find,
    CodingAgent.Tools.Ls
  ]

  def all, do: @tools
end

# ToolAdapter 自动转换为 ReqLLM.Tool
tools = Jido.AI.ToolAdapter.from_actions(CodingAgent.Tools.all())
```

每个 Action 的 schema 直接映射为 LLM 的 tool parameters。Jido 的 `Jido.Action.Schema.to_json_schema/1` 自动完成转换。

---

### J. 测试规格（BDD）

Pi 全项目共 152 个测试。我们移植工具测试和 Agent 集成测试，补充安全/边界场景，TUI/剪贴板测试跳过。
所有测试遵循项目 BDD 规范（Given / When / Then），按 Jido Action 组织。

---

#### J.1 edit Action（26 个）

```elixir
@moduledoc """
Edit Action 测试

基于编码 Agent 架构文档 Section A (edit 设计规格)
共 26 个测试用例，覆盖精确/模糊匹配、CRLF/BOM 保留、安全边界、Pi 历史 bug 回归
"""
```

##### describe "1. 基础替换"

```elixir
test "1.1 精确匹配替换" do
  # Given: 文件内容为 "Hello, world!"
  # When: edit(path, old: "world", new: "testing")
  # Then: 文件变为 "Hello, testing!"，返回 "Successfully replaced" + unified diff
end

test "1.2 文本不存在" do
  # Given: 文件内容为 "Hello, world!"
  # When: edit(path, old: "nonexistent", new: "x")
  # Then: 返回错误 "Could not find the exact text in {path}"
end

test "1.3 多次出现拒绝" do
  # Given: 文件内容为 "foo bar foo baz foo"
  # When: edit(path, old: "foo", new: "qux")
  # Then: 返回错误 "Found 3 occurrences of the text in {path}"
end
```

##### describe "2. 模糊匹配"

```elixir
test "2.1 尾部空格容错" do
  # Given: 文件含 "line one   \n"（3 个尾部空格）
  # When: edit(path, old: "line one\n", new: "replaced\n")（无尾部空格）
  # Then: 模糊匹配成功，替换完成
end

test "2.2 弯单引号容错" do
  # Given: 文件含 \u2018hello\u2019（弯单引号）
  # When: edit(path, old: "'hello'", new: "'world'")（ASCII 单引号）
  # Then: 模糊匹配成功
end

test "2.3 弯双引号容错" do
  # Given: 文件含 \u201CHello\u201D（弯双引号）
  # When: edit(path, old: "\"Hello\"", new: "\"World\"")（ASCII 双引号）
  # Then: 模糊匹配成功
end

test "2.4 Unicode 破折号容错" do
  # Given: 文件含 en-dash \u2013 和 em-dash \u2014
  # When: edit(path, old: 用 ASCII "-")
  # Then: 模糊匹配成功
end

test "2.5 非断行空格容错" do
  # Given: 文件含 \u00A0（NBSP）
  # When: edit(path, old: 用普通空格)
  # Then: 模糊匹配成功
end

test "2.6 精确匹配优先" do
  # Given: 文件为纯 ASCII 内容
  # When: edit(path, old: 精确匹配的文本)
  # Then: 使用精确匹配（非模糊），无规范化副作用
end

test "2.7 模糊也找不到" do
  # Given: 文件内容与 oldText 完全不同
  # When: edit(path, old: "completely different")
  # Then: 精确和模糊都失败，返回 "Could not find" 错误
end

test "2.8 模糊后重复检测" do
  # Given: 文件含两行仅尾部空格不同（"hello   " 和 "hello"）
  # When: edit(path, old: "hello")
  # Then: 模糊正规化后两行相同 → 返回 "Found 2 occurrences"
end
```

##### describe "3. CRLF / BOM 保留"

```elixir
test "3.1 跨平台行尾匹配" do
  # Given: 文件使用 CRLF（\r\n）行尾
  # When: edit(path, old: 使用 LF 的 oldText)
  # Then: 正规化后匹配成功
end

test "3.2 CRLF 保留" do
  # Given: CRLF 文件
  # When: 执行替换
  # Then: 写回文件仍为 CRLF
end

test "3.3 LF 保留" do
  # Given: LF 文件
  # When: 执行替换
  # Then: 写回文件仍为 LF（不会注入 \r\n）
end

test "3.4 混合行尾重复检测" do
  # Given: 文件含 "hello\r\nworld" 和 "hello\nworld"
  # When: edit(path, old: "hello\nworld")
  # Then: 正规化后两处相同 → "Found 2 occurrences"
end

test "3.5 BOM + CRLF 联合保留" do
  # Given: 文件以 \uFEFF 开头 + CRLF 行尾
  # When: 执行替换
  # Then: BOM 和 CRLF 均保留
end
```

##### describe "4. 安全与边界"

```elixir
test "4.1 空文件编辑" do
  # Given: 0 字节文件
  # When: edit(path, old: "", new: "content")
  # Then: 定义明确的行为（成功插入或拒绝空 oldText）
end

test "4.2 超大文件性能" do
  # Given: 10MB 文件
  # When: 执行替换
  # Then: 在合理时间内完成（<5 秒）
end

test "4.3 no-op 检测" do
  # Given: 文件含 "hello"
  # When: edit(path, old: "hello", new: "hello")
  # Then: 返回 "No changes made to {path}"
end

test "4.4 并发编辑" do
  # Given: 同一文件
  # When: 两个 Task 同时执行 edit
  # Then: 不产生数据损坏（原子写入或报错）
end

test "4.5 二进制文件保护" do
  # Given: PNG 图片文件
  # When: edit(path, old: "...", new: "...")
  # Then: 返回错误，不破坏二进制内容
end

test "4.6 路径遍历攻击" do
  # Given: path 为 "../../etc/passwd"
  # When: edit(path, old: "root", new: "hacked")
  # Then: 拒绝操作，路径限制在工作区内
end

test "4.7 目标是目录" do
  # Given: path 指向一个目录
  # When: edit(path, old: "x", new: "y")
  # Then: 返回明确的 "Is a directory" 错误
end
```

##### describe "5. Pi 历史 bug 回归"

```elixir
test "5.1 tilde 路径展开" do
  # Pi bug: edit/read/write 不展开 ~/, LLM 传 ~/file.txt 直接报文件不存在
  # Given: file_path = "~/test_dir/hello.txt" 且文件存在于 $HOME/test_dir/
  # When: edit(path: "~/test_dir/hello.txt", old: "a", new: "b")
  # Then: 正确展开为绝对路径并完成替换
end

test "5.2 无效参数类型防护" do
  # Pi bug #1259: LLM 传了非 string 的 file_path（如 integer/nil），直接崩溃
  # Given: file_path 参数为 nil 或 123
  # When: edit(path: nil, old: "x", new: "y")
  # Then: 返回参数校验错误，不崩溃
end

test "5.3 diff 行号远离文件开头" do
  # Pi bug: 编辑第 338 行时 diff 显示行号从 1 开始
  # Given: 500 行文件，第 338 行含 "target"
  # When: edit(path, old: "target", new: "replaced")
  # Then: 返回的 diff 信息中行号正确显示为 338 附近
end
```

---

#### J.2 bash Action（19 个）

```elixir
@moduledoc """
Bash Action 测试

基于编码 Agent 架构文档 Section B (bash 设计规格)
共 19 个测试用例，覆盖执行、错误、输出管理、进程管理、Pi 历史 bug 回归
"""
```

##### describe "1. 基本执行"

```elixir
test "1.1 简单命令" do
  # Given: 无特殊配置
  # When: bash("echo hello")
  # Then: 输出 "hello\n"，无截断详情
end

test "1.2 命令错误码" do
  # Given: 无特殊配置
  # When: bash("exit 1")
  # Then: 输出含 "Command exited with code 1"
end

test "1.3 命令前缀" do
  # Given: commandPrefix = "export TEST_VAR=hello"
  # When: bash("echo $TEST_VAR")
  # Then: 输出 "hello"
end

test "1.4 前缀和命令输出合并" do
  # Given: commandPrefix = "echo prefix_output"
  # When: bash("echo command_output")
  # Then: 输出同时包含 "prefix_output" 和 "command_output"
end
```

##### describe "2. 错误处理"

```elixir
test "2.1 超时" do
  # Given: timeout = 1 秒
  # When: bash("sleep 5")
  # Then: 输出含 "Command timed out after 1 seconds"
end

test "2.2 不存在的工作目录" do
  # Given: cwd = "/this/directory/does/not/exist"
  # When: bash("echo test")
  # Then: 返回路径不存在错误
end

test "2.3 spawn 失败" do
  # Given: shell 路径为不存在的可执行文件
  # When: bash("echo test")
  # Then: 返回 ENOENT 错误
end
```

##### describe "3. 输出管理"

```elixir
test "3.1 大输出滚动缓冲区" do
  # Given: 无特殊配置
  # When: bash 输出超过 100KB
  # Then: 内存中只保留最近 100KB（尾部），返回 tail 截断结果
end

test "3.2 临时文件创建" do
  # Given: 无特殊配置
  # When: bash 输出超过 50KB
  # Then: 创建临时文件保存完整输出，截断提示含文件路径
end

test "3.3 stderr + stdout 交错" do
  # Given: 命令同时写 stdout 和 stderr
  # When: bash("echo out && echo err >&2")
  # Then: 两个流的内容都被捕获
end

test "3.4 多字节 UTF-8 截断" do
  # Given: 中文输出接近截断边界
  # When: bash 产生大量中文输出
  # Then: 截断点在有效 UTF-8 字符边界，不产生乱码
end
```

##### describe "4. 进程管理"

```elixir
test "4.1 进程树杀死" do
  # Given: 命令 spawn 子进程（如 bash -c "sleep 100 & sleep 100"）
  # When: 超时触发
  # Then: 整棵进程树被杀死，无僵尸进程
end

test "4.2 管道命令信号处理" do
  # Given: 管道命令 "yes | head -5"
  # When: bash 执行
  # Then: 正常完成，SIGPIPE 不导致错误
end

test "4.3 环境变量继承" do
  # Given: 父进程设有环境变量 HOME, PATH
  # When: bash("echo $HOME")
  # Then: 子进程继承父进程环境变量
end
```

##### describe "5. Pi 历史 bug 回归"

```elixir
test "5.1 UTF-8 多字节跨 chunk 边界" do
  # Pi bug #608: 流式输出的中文/emoji 被切断在两个 chunk 之间，出现乱码
  # Given: 命令输出大量中文文本（超过单次 IO buffer）
  # When: bash("python3 -c \"print('你好' * 5000)\"")
  # Then: 输出完整，无乱码，所有字符 UTF-8 合法
end

test "5.2 交互式命令不挂死" do
  # Pi bug #298: git commit 触发编辑器，bash 永远等待用户输入
  # Given: 命令需要交互式输入（如 git commit 无 -m）
  # When: bash("git commit", timeout: 5000)
  # Then: 超时后进程被杀死，返回超时错误，不永久挂起
end

test "5.3 进程组杀死" do
  # Pi bug: abort 只杀父 shell，子进程 (sleep & sleep) 还在跑
  # Given: 命令创建子进程 bash("sleep 100 & sleep 100 & wait")
  # When: 超时触发杀进程
  # Then: 整个进程组被杀死，无残留子进程
end

test "5.4 sh vs bash 语法兼容" do
  # Pi bug #328: 用 sh 执行含 bash 特有语法的命令失败
  # Given: 命令含 bash 语法（如 [[ ]]、数组、<()）
  # When: bash("if [[ -f /etc/hosts ]]; then echo yes; fi")
  # Then: 正确执行（使用 bash 而不是 sh）
end

test "5.5 截断行数计数精确" do
  # Pi bug #921: 截断通知中 "earlier lines" 计数 off-by-one
  # Given: 命令输出 150 行，截断保留后 100 行
  # When: bash("seq 1 150")
  # Then: 截断通知显示 "省略 50 行"（而不是 49 或 51）
end
```

---

#### J.3 read Action（19 个）

```elixir
@moduledoc """
Read Action 测试

基于编码 Agent 架构文档 Section C (read 设计规格)
共 19 个测试用例，覆盖基本读取、分页、截断、图片、文件系统边界、Pi 历史 bug 回归
"""
```

##### describe "1. 基本读取"

```elixir
test "1.1 正常读取" do
  # Given: 3 行文本文件
  # When: read(path)
  # Then: 返回完整内容，truncated = false，details = nil
end

test "1.2 文件不存在" do
  # Given: path 指向不存在的文件
  # When: read(path)
  # Then: 返回 ENOENT 错误
end

test "1.3 空文件" do
  # Given: 0 字节文件
  # When: read(path)
  # Then: 返回空字符串，不报错
end
```

##### describe "2. 分页"

```elixir
test "2.1 offset 参数" do
  # Given: 100 行文件
  # When: read(path, offset: 51)
  # Then: 返回第 51-100 行
end

test "2.2 limit 参数" do
  # Given: 100 行文件
  # When: read(path, limit: 10)
  # Then: 返回前 10 行，提示 "[90 more lines in file. Use offset=11 to continue.]"
end

test "2.3 offset + limit 组合" do
  # Given: 100 行文件
  # When: read(path, offset: 41, limit: 20)
  # Then: 返回第 41-60 行
end

test "2.4 offset=1 边界" do
  # Given: 多行文件
  # When: read(path, offset: 1)
  # Then: 从第 1 行开始（等同于无 offset）
end

test "2.5 offset 越界" do
  # Given: 3 行文件
  # When: read(path, offset: 100)
  # Then: 返回 "Offset 100 is beyond end of file (3 lines total)"
end
```

##### describe "3. 截断"

```elixir
test "3.1 行数截断" do
  # Given: 2500 行文件
  # When: read(path)
  # Then: 截断到 2000 行，提示 "[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]"
end

test "3.2 字节截断" do
  # Given: 500 行 × 200 字符（> 50KB）
  # When: read(path)
  # Then: 按字节截断，提示含 "(50.0KB limit)"
end

test "3.3 首行超大" do
  # Given: 单行 > 50KB
  # When: read(path)
  # Then: firstLineExceedsLimit = true，提示 "Use bash: sed -n '1p' {path} | head -c 51200"
end
```

##### describe "4. 图片处理"

```elixir
test "4.1 MIME 类型检测" do
  # Given: PNG 二进制内容存为 .txt 扩展名
  # When: read(path)
  # Then: 检测为 image/png，返回 base64 图片数据
end

test "4.2 非图片但图片扩展名" do
  # Given: 纯文本内容存为 .png 扩展名
  # When: read(path)
  # Then: 识别为文本，返回文本内容（无 ImageContent）
end
```

##### describe "5. 文件系统边界"

```elixir
test "5.1 截断详情元数据" do
  # Given: 2500 行文件
  # When: read(path)
  # Then: 返回 %{truncated: true, truncated_by: :lines, total_lines: 2500, output_lines: 2000}
end

test "5.2 offset=最后一行" do
  # Given: 100 行文件
  # When: read(path, offset: 100)
  # Then: 只返回最后 1 行
end

test "5.3 符号链接" do
  # Given: 软链接指向真实文件
  # When: read(symlink_path)
  # Then: 返回目标文件内容
end

test "5.4 权限不足" do
  # Given: 文件权限为 000
  # When: read(path)
  # Then: 返回 EACCES 错误
end
```

##### describe "6. Pi 历史 bug 回归"

```elixir
test "6.1 特殊字符文件名" do
  # Pi bug #181: macOS 截图文件名含空格和 unicode 字符，read 失败
  # Given: 文件名为 "截图 2026-02-11 下午3.42.10.png"（含空格和中文）
  # When: read(path: "截图 2026-02-11 下午3.42.10.png")
  # Then: 正常读取，不因路径中的空格或 unicode 而报错
end

test "6.2 tilde 路径展开" do
  # Pi bug: read 不展开 ~/，LLM 传 ~/file.txt 直接报文件不存在
  # Given: 文件存在于 $HOME/test.txt
  # When: read(path: "~/test.txt")
  # Then: 正确展开 ~ 为 $HOME 并读取
end
```

---

#### J.4 write Action（8 个）

```elixir
@moduledoc """
Write Action 测试

基于编码 Agent 架构文档 Section D (write 设计规格)
共 8 个测试用例
"""
```

##### describe "1. 基本写入"

```elixir
test "1.1 创建新文件" do
  # Given: 路径不存在
  # When: write(path, content: "hello world")
  # Then: 文件创建成功，返回 "Successfully wrote N bytes"
end

test "1.2 覆写已有文件" do
  # Given: 文件已存在，内容为 "old"
  # When: write(path, content: "new")
  # Then: 文件内容变为 "new"
end

test "1.3 递归创建父目录" do
  # Given: 路径为 "nested/deep/dir/test.txt"，父目录不存在
  # When: write(path, content: "hello")
  # Then: 所有中间目录被创建，文件写入成功
end
```

##### describe "2. 内容边界"

```elixir
test "2.1 空内容" do
  # Given: content = ""
  # When: write(path, content: "")
  # Then: 创建 0 字节文件
end

test "2.2 UTF-8 多字节" do
  # Given: content 含中文和 emoji "你好 🌍"
  # When: write(path, content: "你好 🌍")
  # Then: 写入成功，读回内容一致
end
```

##### describe "3. 安全与错误"

```elixir
test "3.1 权限不足" do
  # Given: 目标目录无写入权限
  # When: write(path, content: "test")
  # Then: 返回 EACCES 错误
end

test "3.2 路径遍历攻击" do
  # Given: path = "../../etc/crontab"
  # When: write(path, content: "malicious")
  # Then: 拒绝操作，路径限制在工作区内
end

test "3.3 tilde 路径展开" do
  # Pi bug: write 不展开 ~/，文件创建在错误位置
  # Given: file_path = "~/output/result.txt"
  # When: write(path: "~/output/result.txt", content: "data")
  # Then: 正确展开 ~ 为 $HOME 并写入
end
```

---

#### J.5 grep Action（10 个）

```elixir
@moduledoc """
Grep Action 测试

基于编码 Agent 架构文档 Section E (grep 设计规格)
共 10 个测试用例
"""
```

##### describe "1. 基本搜索"

```elixir
test "1.1 单文件搜索" do
  # Given: 文件含 "hello world" 在第 3 行
  # When: grep(pattern: "hello", path: file_path)
  # Then: 输出格式 "file.txt:3: hello world"
end

test "1.2 多文件目录搜索" do
  # Given: 目录下 3 个文件，其中 2 个含匹配
  # When: grep(pattern: "test", path: dir_path)
  # Then: 返回 2 个文件的匹配结果
end

test "1.3 无匹配" do
  # Given: 文件不含目标文本
  # When: grep(pattern: "nonexistent", path: file_path)
  # Then: 返回空结果或 "No matches found"
end
```

##### describe "2. 搜索选项"

```elixir
test "2.1 limit + context" do
  # Given: 文件含 10 处匹配
  # When: grep(pattern: "x", limit: 1, context: 1)
  # Then: 只 1 个匹配 + 上下文行 + "matches limit reached" 通知
end

test "2.2 正则元字符" do
  # Given: 文件含 "foo.bar(baz)"
  # When: grep(pattern: "foo\\.bar\\(")
  # Then: 正则正确匹配
end

test "2.3 literal 模式" do
  # Given: 文件含 "foo.bar(baz)"
  # When: grep(pattern: "foo.bar(", literal: true)
  # Then: 字面量匹配（. 和 ( 不作为正则）
end

test "2.4 大小写不敏感" do
  # Given: 文件含 "Hello World"
  # When: grep(pattern: "hello", ignore_case: true)
  # Then: 匹配成功
end
```

##### describe "3. 截断与过滤"

```elixir
test "3.1 字节截断" do
  # Given: 大量匹配导致输出 > 50KB
  # When: grep(pattern: common_word)
  # Then: 输出被 truncateHead 截断，提示 "50.0KB limit reached"
end

test "3.2 glob 文件过滤" do
  # Given: 目录含 .ex 和 .js 文件
  # When: grep(pattern: "test", glob: "*.ex")
  # Then: 只搜索 .ex 文件
end

test "3.3 二进制文件跳过" do
  # Given: 目录含 PNG 图片和文本文件
  # When: grep(pattern: "test", path: dir_path)
  # Then: 跳过二进制文件，只搜索文本文件
end
```

---

#### J.6 find Action（6 个）

```elixir
@moduledoc """
Find Action 测试

基于编码 Agent 架构文档 Section F (find 设计规格)
共 6 个测试用例
"""
```

##### describe "1. 基本查找"

```elixir
test "1.1 含隐藏文件" do
  # Given: 目录含 .secret/hidden.txt 和 visible.txt
  # When: find(pattern: "*.txt")
  # Then: 两者都出现在结果中
end

test "1.2 嵌套 glob 模式" do
  # Given: 多层嵌套目录结构
  # When: find(pattern: "**/*.ex")
  # Then: 递归匹配所有 .ex 文件
end

test "1.3 空结果" do
  # Given: 目录不含匹配文件
  # When: find(pattern: "*.xyz")
  # Then: 返回空或 "No files found"
end
```

##### describe "2. 过滤与限制"

```elixir
test "2.1 尊重 .gitignore" do
  # Given: .gitignore 含 "ignored.txt"，目录含 ignored.txt
  # When: find(pattern: "*.txt")
  # Then: ignored.txt 不出现
end

test "2.2 结果数限制" do
  # Given: 匹配文件数 > limit
  # When: find(pattern: "*", limit: 5)
  # Then: 只返回 5 个结果
end

test "2.3 符号链接处理" do
  # Given: 目录含指向另一目录的符号链接
  # When: find(pattern: "*.txt")
  # Then: 符号链接目标中的文件也出现（或明确不跟随）
end
```

---

#### J.7 ls Action（6 个）

```elixir
@moduledoc """
Ls Action 测试

基于编码 Agent 架构文档 Section G (ls 设计规格)
共 6 个测试用例
"""
```

##### describe "1. 基本列表"

```elixir
test "1.1 dotfiles 和目录后缀" do
  # Given: 目录含 .hidden-file 和 .hidden-dir/
  # When: ls(path)
  # Then: 都出现，目录有 "/" 后缀
end

test "1.2 空目录" do
  # Given: 空目录
  # When: ls(path)
  # Then: 返回 "(empty directory)"
end

test "1.3 排序验证" do
  # Given: 目录含 Zebra.txt, apple.txt, Banana.txt
  # When: ls(path)
  # Then: 按大小写不敏感字母序排列（apple, Banana, Zebra）
end
```

##### describe "2. 错误与边界"

```elixir
test "2.1 路径是文件" do
  # Given: path 指向文件而非目录
  # When: ls(path)
  # Then: 返回 "Not a directory" 错误
end

test "2.2 路径不存在" do
  # Given: path 不存在
  # When: ls(path)
  # Then: 返回 "Path not found" 错误
end

test "2.3 大目录截断" do
  # Given: 目录含 600 个文件
  # When: ls(path)
  # Then: 截断到 500 条目，提示剩余数量
end
```

---

#### J.8 截断系统（14 个）

```elixir
@moduledoc """
截断系统单元测试

基于编码 Agent 架构文档 Section H (截断系统设计)
共 14 个测试用例，覆盖三种截断策略 + UTF-8 边界 + 边界条件 + 截断通知
"""
```

##### describe "1. truncate_head"

```elixir
test "1.1 不需截断" do
  # Given: 10 行 / 100 字节的小内容
  # When: truncate_head(content)
  # Then: 原样返回，truncated = false
end

test "1.2 行数限制" do
  # Given: 2500 行内容
  # When: truncate_head(content, max_lines: 2000)
  # Then: 保留前 2000 行，truncated_by = :lines
end

test "1.3 字节限制" do
  # Given: 100 行 × 1KB（总 100KB）
  # When: truncate_head(content, max_bytes: 50_000)
  # Then: 按字节截断，truncated_by = :bytes
end

test "1.4 首行超限" do
  # Given: 单行 > 50KB
  # When: truncate_head(content)
  # Then: content = ""，first_line_exceeds_limit = true
end

test "1.5 空字符串" do
  # Given: content = ""
  # When: truncate_head("")
  # Then: 返回 ""，truncated = false
end
```

##### describe "2. truncate_tail"

```elixir
test "2.1 不需截断" do
  # Given: 10 行小内容
  # When: truncate_tail(content)
  # Then: 原样返回，truncated = false
end

test "2.2 行数限制" do
  # Given: 3000 行内容
  # When: truncate_tail(content, max_lines: 2000)
  # Then: 保留后 2000 行
end

test "2.3 字节限制" do
  # Given: 100 行 × 1KB
  # When: truncate_tail(content, max_bytes: 50_000)
  # Then: 从末尾保留 50KB
end

test "2.4 末行超限 UTF-8 安全" do
  # Given: 末行含中文 > 50KB
  # When: truncate_tail(content)
  # Then: 截断在 UTF-8 字符边界，last_line_partial = true，不产生乱码
end

test "2.5 恰好在限制值" do
  # Given: 内容恰好 2000 行 / 恰好 50000 字节
  # When: truncate_tail(content)
  # Then: 不截断，truncated = false（off-by-one 验证）
end
```

##### describe "3. truncate_line"

```elixir
test "3.1 短行不截断" do
  # Given: 100 字符的行
  # When: truncate_line(line, max: 500)
  # Then: 原样返回
end

test "3.2 长行截断" do
  # Given: 800 字符的行
  # When: truncate_line(line, max: 500)
  # Then: 截断到 500 字符 + "... [truncated]"
end
```

##### describe "4. 截断通知可操作性"

```elixir
test "4.1 read 截断通知含续读指引" do
  # Pi bug #134: 截断后 LLM 不知道怎么获取完整内容
  # Given: 2500 行文件，截断到 2000 行
  # When: read(path) 触发截断
  # Then: 通知包含 "Use offset=2000 to continue"
end

test "4.2 bash 截断通知含原始大小" do
  # Pi bug: 截断通知中限制值与实际不一致
  # Given: 命令输出 80KB
  # When: bash("cat large.log") 触发截断
  # Then: 通知包含实际截断阈值和原始大小
end
```

#### J.9 Agent 集成测试（20 个）

```elixir
@moduledoc """
Agent 集成测试

验证我们的 Action 模块在 Jido 管道中的表现。
Jido/jido_ai/ReqLLM 框架层由各自的测试覆盖，我们不重复。
共 20 个测试用例，含 7 个 Pi 历史 bug 回归
"""
```

##### describe "1. Action 管道"

```elixir
test "1.1 冒烟测试" do
  # Given: Agent 配置完整（model + tools）
  # When: 发送简单文本提示
  # Then: 收到文本回复，无报错
end

test "1.2 单工具调用" do
  # Given: Agent 注册了 read Action
  # When: 提示 "读取 test.txt"
  # Then: LLM 请求 read → 执行 Action → 结果回传 → LLM 最终回答含文件内容
end

test "1.3 多工具连续调用" do
  # Given: Agent 注册了所有 7 个 Action
  # When: 提示需要先 read 再 edit 的任务
  # Then: LLM 连续调用多个 Action，每个都正确执行
end

test "1.4 steering 中断" do
  # Given: Agent 正在执行 bash("sleep 30")
  # When: 发送 steer 消息
  # Then: bash Action 杀进程 + 清理资源，剩余工具返回 "Skipped"
end

test "1.5 follow-up 续接" do
  # Given: Agent 完成第一轮回答
  # When: 追加 follow-up 消息
  # Then: Agent 继续执行，上下文保留
end

test "1.6 abort 中断" do
  # Given: Agent 正在执行中
  # When: 发送 abort 信号
  # Then: 临时文件清理，子进程全部杀死
end

test "1.7 并发锁" do
  # Given: Agent 正在处理请求
  # When: 同时发送第二个 prompt
  # Then: 第二个请求被拒绝或排队（不并发执行）
end

test "1.8 上下文保持" do
  # Given: 第一轮对话中 LLM 调用了 read Action
  # When: 第二轮对话引用第一轮读取的内容
  # Then: 工具结果在多轮上下文中正确传递
end
```

##### describe "2. Anthropic E2E"

```elixir
@tag :e2e
@tag provider: :anthropic

test "2.1 文本提示" do
  # Given: 真实 Anthropic API 配置
  # When: 发送 "What is 2+2?"
  # Then: 收到含 "4" 的回答
end

test "2.2 工具调用" do
  # Given: 真实 API + 注册 read Action
  # When: 提示读取真实文件
  # Then: Action 被调用，参数正确传递，结果正确回传
end

test "2.3 流式事件" do
  # Given: 真实 API
  # When: 发送提示
  # Then: 事件序列正确：start → delta(s) → end
end

test "2.4 多轮上下文" do
  # Given: 真实 API
  # When: 发送两轮对话，第二轮引用第一轮
  # Then: LLM 记忆正确
end
```

##### describe "3. 路由"

```elixir
test "3.1 Signal 路由正确性" do
  # Given: 我们的路由配置
  # When: 发送 react.input Signal
  # Then: 正确分发到 ReAct Strategy
end
```

##### describe "4. Pi 历史 bug 回归"

```elixir
test "4.1 并发 prompt 竞态防护" do
  # Pi bug #403: 同时调两次 agent.chat()，状态被覆盖导致数据损坏
  # Given: Agent 正在处理一个请求（流式输出中）
  # When: 同时发送第二个 prompt
  # Then: 第二个请求被拒绝（raise 或返回 {:error, :busy}），不会并发执行
end

test "4.2 孤儿 tool_result 清理" do
  # Pi bug #1454/#1455: 中断的 tool_call 留下无主 tool_result，后续请求 API 400
  # Given: Agent 执行两个 tool_call，第一个完成后第二个被中断
  # When: 下一轮对话发送给 LLM
  # Then: 孤儿 tool_result（无对应 tool_call）被自动清理或补全，API 不报 400
end

test "4.3 429 不触发压缩" do
  # Pi bug #1038: HTTP 429 rate limit 被误判为上下文溢出，错误触发压缩
  # Given: LLM API 返回 HTTP 429 Too Many Requests
  # When: Agent 处理该错误
  # Then: 进入重试逻辑（指数退避），不触发上下文压缩
end

test "4.4 压缩后排队消息恢复" do
  # Pi bug #1312: auto-compaction 期间排队的用户消息丢失
  # Given: Agent 正在执行压缩
  # When: 用户在压缩期间发送新消息
  # Then: 压缩完成后，排队的消息被正常处理，不丢失
end

test "4.5 非数组 content 不崩溃" do
  # Pi bug #1434: message.content 是 string/nil 时 .filter() 崩溃
  # Given: LLM 返回 content 为纯字符串（非 list）
  # When: Agent 解析该响应
  # Then: 正常处理，不因 content 类型异常而崩溃
end

test "4.6 多 tool_call 结果不错位" do
  # Pi bug #1446: 一轮返回多个 tool_call，结果 FIFO 错位导致工具结果张冠李戴
  # Given: LLM 一次返回 3 个 tool_call (read A, read B, read C)
  # When: 并发或顺序执行后回传结果
  # Then: 每个 tool_result 精确对应原始 tool_call_id，不错位
end

test "4.7 retry 在工具执行完成后才 resolve" do
  # Pi bug #1465: retry 在 message_end 就 resolve，但 tool 还没执行完
  # Given: LLM 返回 tool_call，API 曾 retry 过
  # When: Agent 执行 tool_call
  # Then: 整个循环（含工具执行）完成后才标记为成功
end
```

**以下由 Jido/jido_ai 自身测试覆盖，我们不重复（7 个）：**
- ~~Agent 进程启动/停止~~ → Jido DynamicSupervisor 测试
- ~~Agent 崩溃恢复~~ → Jido Supervisor 测试
- ~~Directive 执行顺序~~ → Jido drain loop 测试
- ~~状态机转换~~ → jido_ai ReAct Machine 测试
- ~~max_iterations 超限~~ → jido_ai Machine 测试
- ~~Request async/await~~ → jido_ai Request 模块测试
- ~~多 Agent 并发~~ → Jido Registry + DynamicSupervisor 测试

---

#### J.10 留位测试（预留接口和测试骨架）

##### describe "多提供商 E2E"（12 个留位）

```elixir
# 参数化测试骨架：同一套 4 个测试跑多个提供商
for provider <- [:openai, :google, :deepseek] do
  describe "#{provider} E2E" do
    @tag provider: provider
    @tag :e2e
    @tag :reserved

    setup do
      model = provider_model(unquote(provider))
      {:ok, model: model}
    end

    test "文本提示", %{model: model} do
      # Given: 真实 #{provider} API 配置
      # When: 发送简单问题
      # Then: 收到合理回答
    end

    test "工具调用", %{model: model} do
      # Given: 真实 API + 注册 Action
      # When: 提示需要工具的任务
      # Then: Action 被调用，参数正确传递
    end

    test "流式事件", %{model: model} do
      # Given: 真实 API
      # When: 发送提示
      # Then: 事件序列 start → delta(s) → end
    end

    test "多轮上下文", %{model: model} do
      # Given: 真实 API
      # When: 两轮对话
      # Then: 记忆正确
    end
  end
end

# 运行方式：
# mix test --only provider:openai
# mix test --only e2e
# mix test --exclude e2e
```

**第二批留位（按需加）：** Groq（推理速度）、xAI/Grok（溢出格式）、Ollama（本地模型）、Mistral（9 字符 ID）

##### describe "图片配置"（4 个留位）

```elixir
@tag :reserved

test "图片处理开关" do
  # Given: Agent 配置 block_images: true
  # When: read 返回图片文件
  # Then: 图片不发送给 LLM
end

test "图片过滤层" do
  # Given: read 返回图片数据
  # When: 发送给无图片能力的模型
  # Then: 图片在发送前被过滤，节省 token
end

test "图片大小限制配置" do
  # Given: 配置 max_image_size: 1_000_000
  # When: read 返回 2MB 图片
  # Then: 自动缩放到限制内
end

test "配置持久化" do
  # Given: 设置 block_images: true
  # When: Agent 重启
  # Then: 配置恢复
end
```

##### describe "路径扩展"（6 个留位）

```elixir
@tag :reserved

# macOS 特有（如需跨平台）
test "NFD 规范化路径" do
  # Given: macOS APFS 文件系统，文件名含重音符
  # When: read(path) 使用 NFC 路径
  # Then: NFD 回退匹配成功
end

test "弯引号路径" do
  # Given: macOS 截图文件名含 U+2019
  # When: read(path) 使用 ASCII 引号
  # Then: 回退匹配成功
end

test "AM/PM 窄空格路径" do
  # Given: macOS 截图时间含 U+202F
  # When: read(path) 使用普通空格
  # Then: 回退匹配成功
end

# Linux 服务器场景
test "NFS/网络路径" do
  # Given: 文件在 NFS 挂载目录
  # When: read/write 操作
  # Then: 正常工作（延迟可能较高）
end

test "Docker 内路径映射" do
  # Given: 容器内路径与宿主不同
  # When: 工具使用容器内路径
  # Then: 正确解析
end

test "超长路径（>4096 字符）" do
  # Given: 路径长度接近 PATH_MAX
  # When: read/write 操作
  # Then: 返回明确错误或正常工作
end
```

---

#### 跳过的测试

| 模块 | Pi 测试数 | 不需要原因 |
|------|----------|-----------|
| TUI 截断组件 | 9 | 我们用 LiveView，不做终端 UI |
| 终端列宽截断 | 6 | 同上，终端列宽与 Web 无关 |
| 剪贴板图片读取 | 4 | 桌面剪贴板是本地 CLI 功能，Web 端用文件上传 |
| 剪贴板 BMP→PNG | 1 | 同上 |
| **跳过小计** | **20** | |

#### 测试总计

| Action / 模块 | 数量 | 其中 Pi bug 回归 | 状态 |
|---------------|------|-----------------|------|
| edit Action | 26 | +3 | 必做 |
| bash Action | 19 | +5 | 必做 |
| read Action | 19 | +2 | 必做 |
| write Action | 8 | +1 | 必做 |
| grep Action | 10 | — | 必做 |
| find Action | 6 | — | 必做 |
| ls Action | 6 | — | 必做 |
| 截断系统 | 14 | +2 | 必做 |
| Agent 集成 | 20 | +7 | 必做 |
| **必做合计** | **128** | **+20** | |
| 多提供商 E2E（OpenAI/Gemini/DeepSeek） | 12 | — | 留位 |
| 图片配置 | 4 | — | 留位 |
| 路径扩展（macOS + NFS + Docker + 超长） | 6 | — | 留位 |
| **留位合计** | **22** | | |
| **总计（含留位）** | **150** | | |
| 不需要的（Pi TUI/剪贴板） | 20 | | 跳过 |
| 不重复的（Jido/jido_ai 自身覆盖） | 7 | | 由框架测试 |

---

## 四、LLM Provider 适配层

### 4.1 架构：注册表 + Adapter 模式

这是整个系统中**抽象层数最多、工程量最大**的部分。不同 LLM 提供商的 API 格式差异巨大，需要一个统一的适配层。

```
┌──────────────────────────────────────────────────────────┐
│                    统一调用接口                            │
│  stream(model, context, options) → EventStream            │
│  streamSimple(model, context, options) → EventStream      │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                   API 注册表                              │
│  registerApi(apiType, streamFn)                           │
│  getStreamFn(apiType) → StreamFunction                    │
└──────────────────────────┬───────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼──────┐  ┌───────▼──────┐  ┌───────▼──────┐
│  Anthropic   │  │   OpenAI     │  │   Google     │  ...
│  Adapter     │  │  Completions │  │   Gemini     │
│              │  │   Adapter    │  │   Adapter    │
│  Messages    │  ├──────────────┤  └──────────────┘
│  API         │  │   OpenAI     │
└──────────────┘  │  Responses   │
                  │   Adapter    │
                  └──────────────┘
```

### 4.2 支持的提供商（18+）

| 提供商 | API 类型 | 特殊处理 |
|-------|---------|---------|
| Anthropic | anthropic-messages | 缓存控制、thinking 块、签名 |
| OpenAI | openai-completions | reasoning_effort、JSON 字符串参数 |
| OpenAI (新) | openai-responses | 超长 ID 处理、加密 reasoning |
| Google Gemini | google-generative-ai | `<thinking>` 标签解析、thoughtSignature |
| AWS Bedrock | anthropic-messages (代理) | 区域路由、IAM 认证 |
| Azure OpenAI | openai-completions (代理) | 部署名映射 |
| GitHub Copilot | openai-completions (代理) | OAuth 令牌、特殊 header |
| xAI (Grok) | openai-completions | 自定义溢出错误格式 |
| Groq | openai-completions | 速率限制敏感 |
| Cerebras | openai-completions | 400/413 无 body = 溢出 |
| Mistral | openai-completions | 9 字符 ID 限制、thinking 转标签 |
| OpenRouter | openai-completions | 路由选项、provider 过滤 |
| z.ai | openai-completions | 无声溢出检测 |
| Ollama | openai-completions | 本地模型 |
| LM Studio | openai-completions | 本地模型 |
| HuggingFace | openai-completions | - |
| Kimi | openai-completions | - |
| Vercel Gateway | openai-completions | 路由选项 |

大部分提供商复用 OpenAI Completions 格式，但每家都有微妙的差异需要特殊处理。

### 4.3 核心差异对照

#### Tool Call 格式

| 提供商 | 参数格式 | ID 格式 | ID 长度限制 |
|-------|---------|---------|-----------|
| Anthropic | JSON 对象（流式 partial JSON） | `[a-zA-Z0-9_-]` | 64 字符 |
| OpenAI Completions | JSON 字符串（流式文本拼接） | 任意字符串 | 40 字符 |
| OpenAI Responses | JSON 对象（流式 partial JSON） | `call_id\|item_id` | 450+ 字符，需截断 |
| Mistral | JSON 字符串 | 恰好 9 个字母数字 | 9 字符 |

**ID 规范化**：

```go
// Anthropic: 严格格式
id = regexp.MustCompile(`[^a-zA-Z0-9_-]`).ReplaceAllString(id, "_")
if len(id) > 64 { id = id[:64] }

// Mistral: 恰好 9 个字符
id = generateAlphanumeric(9)

// OpenAI Responses: 拆分复合 ID
parts := strings.SplitN(id, "|", 2)
callId, itemId := parts[0], parts[1]
```

#### 流式 Tool 参数解析

Anthropic 和 OpenAI Responses 返回 partial JSON：
```
第 1 帧: {"path": "/sr
第 2 帧: c/main.go", "con
第 3 帧: tent": "hello"}
```

需要专门的 streaming JSON parser 处理不完整的 JSON，在每一帧尝试解析出尽可能多的字段。

OpenAI Completions 返回的是 JSON 字符串的增量，直接拼接后再解析。

#### 系统提示

| 提供商 | 方式 |
|-------|------|
| Anthropic | `system` 参数（独立字段） |
| OpenAI Completions | 第一条消息 `role: "system"` 或 `"developer"` |
| OpenAI Responses | `instructions` 参数 |
| Google | `systemInstruction` 参数 |

#### 思考/推理内容

| 提供商 | 请求 | 响应 |
|-------|------|------|
| Anthropic | `thinking: { type: "enabled", budget_tokens: N }` 或 `{ type: "adaptive" }` | `type: "thinking"` 内容块 + signature |
| OpenAI | `reasoning_effort: "low"\|"medium"\|"high"` | `reasoning_content` / `reasoning` / `reasoning_text` 字段（三种名称） |
| Google | 内嵌在 text 中，`<thinking>` 标签 | `thoughtSignature` 字段 |
| Mistral | 不原生支持 | 转换为 `<thinking>` 标签包裹的文本 |

#### Token 计算

| 提供商 | Input | Output | 缓存 |
|-------|-------|--------|------|
| Anthropic | `input_tokens` | `output_tokens` | `cache_read_input_tokens` + `cache_creation_input_tokens`，不返回 total |
| OpenAI Completions | `prompt_tokens - cached_tokens` | `completion_tokens + reasoning_tokens` | `prompt_tokens_details.cached_tokens` |
| OpenAI Responses | `input_tokens - cached_tokens` | `output_tokens` | `usage_details` |
| Google | `inputTokenCount` | `outputTokenCount` | - |

### 4.4 上下文溢出检测

每个提供商的溢出错误格式不同，需要逐个匹配：

```go
var overflowPatterns = []string{
    `(?i)prompt is too long`,                    // Anthropic
    `(?i)exceeds the context window`,            // OpenAI
    `(?i)input token count.*exceeds`,            // Google
    `(?i)maximum prompt length is \d+`,          // xAI/Grok
    `(?i)reduce the length of the messages`,     // Groq
}

// 特殊情况：
// Cerebras/Mistral: HTTP 400 或 413 无 body → 判定为溢出
// z.ai: 无错误但 usage.input > contextWindow → 无声溢出
```

### 4.5 孤立工具调用修复

当对话历史中出现 assistant 发了 tool_call 但后面没有 tool_result 时（中途中断、错误等），必须自动补全：

```go
// 扫描消息，找到孤立的 tool_call
for _, msg := range messages {
    if msg.Role == "assistant" {
        for _, call := range msg.ToolCalls {
            pendingCalls[call.ID] = call
        }
    }
    if msg.Role == "toolResult" {
        delete(pendingCalls, msg.ToolCallID)
    }
}

// 补全缺失的 tool_result
for id, call := range pendingCalls {
    inject := ToolResultMessage{
        ToolCallID: id,
        ToolName:   call.Name,
        Content:    "No result provided",
        IsError:    true,
    }
    // 插入到对应 assistant 消息之后
}
```

不补全的话，API 会直接拒绝请求。

### 4.6 消息格式转换

发给 LLM 前，需要做两层转换：

```
AgentMessage[] (应用层，含自定义消息类型)
       │
       ▼ transformContext (裁剪上下文、注入外部数据)
       │
       ▼ convertToLlm (过滤 UI-only 消息，转为标准格式)
       │
       ▼ transformMessages (跨模型兼容处理)
       │  ├─ 同模型：保留签名
       │  ├─ 跨模型：删除签名，转为通用格式
       │  └─ 补全孤立 tool_call
       │
Message[] (LLM API 层)
```

### 4.7 Adapter 实现模板

每个 Adapter 需要实现的核心逻辑：

```go
type LLMAdapter interface {
    // 构建请求体
    BuildRequest(model Model, context Context, options Options) ([]byte, error)

    // 解析流式事件
    ParseStreamEvent(raw []byte, partial *AssistantMessage) (*AgentEvent, error)

    // 构建最终消息
    BuildFinalMessage(partial *AssistantMessage, usage Usage) AssistantMessage

    // 格式化工具定义
    FormatTools(tools []Tool) interface{}

    // 格式化消息历史
    FormatMessages(messages []Message) interface{}

    // 规范化 tool call ID
    NormalizeToolCallID(id string) string

    // 检测上下文溢出
    IsContextOverflow(err error, statusCode int) bool

    // 解析 token 用量
    ParseUsage(raw interface{}) Usage
}
```

对于只支持 Anthropic 的最小实现，只需要一个 Adapter。但架构上应该预留接口，方便后续扩展。

---

## 五、会话持久化

### 5.1 Pi 的方案：树形 JSONL

每个条目有 `id` + `parentId`，形成树形结构：

```jsonl
{"type":"session","version":3,"id":"abc","timestamp":"...","cwd":"..."}
{"type":"message","id":"def","parentId":"abc","message":{"role":"user","content":"..."}}
{"type":"message","id":"ghi","parentId":"def","message":{"role":"assistant","content":"..."}}
{"type":"compaction","id":"jkl","parentId":"ghi","summary":"...","firstKeptEntryId":"..."}
{"type":"model_change","id":"mno","parentId":"jkl","provider":"anthropic","modelId":"..."}
```

支持从任意节点分支（fork），切换分支时自动生成分支摘要。

### 5.2 我们的方案：文件夹 + SQLite

详见 [tape-storage-redesign.md](./tape-storage-redesign.md)。

核心差异：
- 按阶段分目录存储（而非单文件）
- SQLite 索引层支持高效查询
- 人工可读（直接 `ls` + `cat`）
- 不需要 archive 机制

---

## 六、上下文压缩

### 6.1 触发条件

```
shouldCompact = contextTokens > (contextWindow - reserveTokens)
```

- `reserveTokens`：保留给新请求和输出的 token 数（默认 16384）
- `keepRecentTokens`：保留最近消息的 token 数（默认 20000）

### 6.2 压缩流程

```
1. 估算 token 数（chars/4 启发式，图片 ~1200 tokens）
2. 从最新消息往回遍历，找到切割点（保留最近 20000 tokens）
3. 切割点必须在有效边界（user/assistant 消息，不能在 toolResult 中间）
4. 如果切在 assistant 消息中间（带 tool calls），生成转折摘要
5. 用 LLM 生成结构化摘要：
   - Goal（目标）
   - Constraints & Preferences（约束与偏好）
   - Progress: Done / In Progress / Blocked（进度）
   - Key Decisions（关键决策）
   - Next Steps（后续步骤）
   - Critical Context（关键上下文）
6. 提取文件操作记录（read/write/edit）附加到摘要末尾
7. 如果有前次压缩，使用 UPDATE 提示增量更新摘要
```

---

## 七、测试策略

### 7.1 三层测试

| 层级 | Mock 策略 | 速度 | 覆盖 |
|------|----------|------|------|
| 单元 | Mock LLM 流（MockAssistantStream） | 快 | 事件序列、状态转移、树结构不变性 |
| 集成 | 真实文件 I/O + Mock LLM | 中 | 会话持久化、压缩、分支、迁移 |
| E2E | 真实 LLM API 调用 | 慢（120s 超时） | 多提供商兼容性、工具执行 |

### 7.2 关键测试场景

**Agent Loop：**
- 基础消息流（事件序列验证）
- 工具调用 + 执行 + 结果回传
- steering 消息中断剩余工具
- follow-up 消息续接
- abort 信号中断
- 并发控制（重复 prompt 抛异常）

**工具：**
- edit：精确匹配、模糊匹配、多次出现拒绝、BOM 保留、CRLF 恢复
- bash：超时、输出截断、进程树杀死、abort
- read：大文件分页、图片处理、macOS 路径

**会话：**
- 树结构 parentId 链正确性
- 分支和 fork 操作
- 压缩后重载恢复
- 版本迁移（v1→v2→v3）
- 损坏文件恢复

### 7.3 Mock 工具

```go
// MockLLMStream: 模拟 LLM 流式响应
type MockLLMStream struct {
    events []AgentEvent
}

func (m *MockLLMStream) Push(event AgentEvent) { ... }
func (m *MockLLMStream) End(result AssistantMessage) { ... }

// 使用方式：
stream := NewMockLLMStream()
stream.Push(StartEvent{})
stream.Push(TextDeltaEvent{Delta: "hello"})
stream.Push(DoneEvent{StopReason: "stop"})
```

---

## 八、工作量评估

### 只支持 Anthropic 的最小可用版本

| 模块 | 行数估算 | 说明 |
|------|---------|------|
| Agent Loop | ~500 | 双层循环 + 中断 + abort + 事件流 |
| edit 工具 | ~400 | 两层匹配 + Unicode + BOM + diff |
| bash 工具 | ~350 | 缓冲区 + 进程树 + 超时 |
| read 工具 | ~250 | 分页 + 图片 + 路径兼容 |
| write + grep + find + ls | ~300 | 相对简单 |
| 截断系统 | ~200 | head + tail + line + UTF-8 边界 |
| Anthropic Adapter | ~600 | 请求构建 + 流式解析 + 格式转换 |
| Adapter 接口层 | ~200 | 统一接口 + 注册表 + 消息转换 |
| 存储层 | ~500 | 文件夹 + SQLite |
| HTTP API / 通信协议 | ~400 | 供外部调用 |
| 错误处理 + 消息格式化 | ~300 | 溢出检测 + 孤立调用修复 + 错误消息 |
| **代码合计** | **~4000** | |
| 测试 | ~3000 | 三层测试 |
| **总计** | **~7000** | |

### 后续扩展

增加一个 OpenAI 提供商：+400 行（Adapter + 测试）
增加上下文压缩：+500 行
增加会话分支：+600 行
增加扩展系统：+1000 行

---

## 九、语言选择：Go vs Elixir/OTP

### 9.1 两种产品形态

| 形态 | 适合语言 | 典型场景 |
|------|---------|---------|
| **独立 CLI 工具** | Go | 像 git 一样跨项目使用，单二进制分发 |
| **嵌入式 Agent** | Elixir | 嵌入到现有 Elixir/Phoenix 系统（如 ZCPG） |

如果目标是做独立 CLI，Go 是最佳选择。如果目标是在现有 Elixir 系统中嵌入 Agent 能力，Elixir/OTP 是更自然的选择。

### 9.2 Go 生态的 LLM Adapter 层

Go 已有现成的多提供商统一库，不需要从零构建 Adapter 层：

| 库 | 特点 | 支持的提供商 | 适用度 |
|---|------|------------|--------|
| **JoakimCarlsson/ai** | 统一 Provider 接口 + 工具调用 + 流式 | Anthropic, OpenAI, Google, Groq, DeepSeek | ★★★★★ 最匹配 |
| **bellman** | 抽象 Backend 接口，支持工具调用 | Anthropic, OpenAI, Google | ★★★★☆ |
| **multi-llm-provider-go** | Adapter 模式，统一接口 | Anthropic, OpenAI, Google, Groq | ★★★☆☆ |
| **LangChainGo** | 完整框架，包含 Chain / Memory / Agent | OpenAI, Anthropic, Google, Ollama | ★★☆☆☆ 太重 |

#### JoakimCarlsson/ai —— 最推荐

```go
// 统一的 Provider 接口
type Provider interface {
    ChatCompletion(ctx context.Context, req ChatCompletionRequest) (*ChatCompletionResponse, error)
    StreamCompletion(ctx context.Context, req ChatCompletionRequest) (<-chan StreamEvent, error)
}

// 创建不同提供商
anthropicProvider := anthropic.New(apiKey)
openaiProvider := openai.New(apiKey)

// 统一调用
resp, err := anthropicProvider.ChatCompletion(ctx, ChatCompletionRequest{
    Model:    "claude-sonnet-4-20250514",
    Messages: messages,
    Tools:    tools,
})
```

优势：
- 接口设计干净，与我们的 LLMAdapter 接口高度一致
- 原生支持流式和工具调用
- 可以直接用，也可以包一层适配我们的 Agent Loop

#### 自建 vs 复用

| 方案 | 工作量 | 灵活性 | 维护成本 |
|------|--------|--------|---------|
| 直接用 JoakimCarlsson/ai | ~100 行封装 | 受限于库的抽象 | 低，跟随上游 |
| 基于它扩展 | ~300 行 | 高，可加自定义逻辑 | 中 |
| 完全自建 | ~800 行 | 完全控制 | 高 |

**推荐**：基于 JoakimCarlsson/ai 扩展。用它处理 HTTP 请求和基本解析，自己加溢出检测、孤立工具调用修复、ID 规范化等 Agent 特有逻辑。

### 9.3 Elixir/OTP 作为 Agent 运行时

OTP 的核心原语与 Agent 概念有天然的映射关系：

#### OTP 原语 → Agent 概念

| OTP 原语 | Agent 概念 | 说明 |
|---------|-----------|------|
| **GenServer** | Agent Session | 有状态的会话进程，handle_call/cast 处理用户输入 |
| **进程邮箱** | Steering 消息 | 用户中断消息天然排队，`receive` 在工具执行间隙检查 |
| **Task** | 工具执行 | `Task.async` 执行工具，主进程可随时 `Task.shutdown` 中断 |
| **Supervisor** | 容错管理 | Agent 进程崩溃自动重启，保持会话数据 |
| **DynamicSupervisor** | 多会话管理 | 动态创建/销毁 Agent 进程 |
| **ETS** | 会话缓存 | 内存级读写，进程崩溃后 ETS 表仍可保留 |
| **GenStage / Flow** | 事件流 | 背压感知的事件分发，天然支持 subscribe 模式 |

#### Agent Loop 的 OTP 实现思路

```elixir
defmodule Agent.Session do
  use GenServer

  # 用户发消息 → GenServer.call
  def prompt(pid, message), do: GenServer.call(pid, {:prompt, message}, :infinity)

  # 用户中断 → GenServer.cast（异步，不阻塞）
  def steer(pid, message), do: GenServer.cast(pid, {:steer, message})

  # === 内部实现 ===

  def handle_call({:prompt, message}, from, state) do
    # 启动 Agent Loop，完成后 reply
    {:noreply, %{state | caller: from, pending: [message]}}
    |> run_loop()
  end

  def handle_cast({:steer, message}, state) do
    # steering 消息存入队列，工具执行间隙检查
    {:noreply, %{state | steering: state.steering ++ [message]}}
  end

  defp run_loop(state) do
    # 外层循环：处理 follow-up
    case run_inner_loop(state) do
      {:follow_up, new_state} -> run_loop(new_state)
      {:done, new_state} ->
        GenServer.reply(new_state.caller, build_result(new_state))
        {:noreply, new_state}
    end
  end

  defp run_inner_loop(state) do
    # 内层循环：LLM 调用 + 工具执行
    # 1. 调用 LLM（流式）
    # 2. 解析 tool calls
    # 3. 顺序执行每个工具，间隙检查 steering
    # 4. 收集结果，继续或退出
  end
end
```

#### 工具执行与中断

```elixir
defp execute_tools(tool_calls, state) do
  Enum.reduce_while(tool_calls, {[], state}, fn call, {results, st} ->
    # 执行工具（用 Task 包装，支持超时和中断）
    task = Task.async(fn -> execute_tool(call) end)

    case Task.yield(task, @tool_timeout) || Task.shutdown(task) do
      {:ok, result} ->
        # 检查 steering 消息
        case check_steering(st) do
          nil -> {:cont, {[result | results], st}}
          steer_msg ->
            # 中断：剩余工具返回错误结果
            {:halt, {[skip_result(call) | [result | results]], inject_steering(st, steer_msg)}}
        end
      nil ->
        {:cont, {[timeout_result(call) | results], st}}
    end
  end)
end

defp check_steering(state) do
  # 非阻塞检查进程邮箱中的 steering 消息
  receive do
    {:"$gen_cast", {:steer, msg}} -> msg
  after
    0 -> nil
  end
end
```

#### Elixir 特有优势

1. **热代码升级**：Agent 进程运行中可以升级代码，不中断会话
2. **分布式**：多节点部署时，Agent 进程可以透明迁移
3. **背压**：GenStage 天然支持事件流的背压控制
4. **模式匹配**：解析 LLM 流式响应时，pattern matching 比 if/switch 更清晰
5. **二进制处理**：Elixir 的 binary pattern matching 处理 UTF-8 边界比 Go 更优雅

```elixir
# UTF-8 边界感知截断（Elixir 天然支持）
defp truncate_utf8(<<>>, _limit), do: <<>>
defp truncate_utf8(binary, limit) when byte_size(binary) <= limit, do: binary
defp truncate_utf8(binary, limit) do
  # binary_part + 自动处理 UTF-8 边界
  binary
  |> binary_part(0, limit)
  |> ensure_valid_utf8()
end
```

### 9.4 Elixir LLM 生态（2026 年 2 月现状）

#### 全景对比

| 库 | Hex 包名 | 版本 | 最近发布 | 下载量 | Stars | 多提供商 | 工具调用 | 流式 |
|---|---------|------|---------|--------|-------|---------|---------|------|
| **LangChain** | `langchain` | 0.5.2 | 2026-02-11 | 47 万 | 1100 | 9+ | ✓ | ✓ |
| **ReqLLM** | `req_llm` | 1.5.1 | 2026-02-04 | 3 万 | 383 | 45+ | ✓ | ✓ |
| **OpenaiEx** | `openai_ex` | 0.9.18 | 2025-10-12 | 28 万 | 206 | OpenAI 兼容 | ✓ | ✓ |
| **Anthropix** | `anthropix` | 0.6.2 | 2025-06-13 | 9.4 万 | 52 | 仅 Anthropic | ✓ | ✓ |
| **Jido** | `jido` | 2.0.0-rc.4 | 2026-02-07 | 1.6 万 | 887 | 通过 jido_ai | ✓ | ✓ |
| **InstructorLite** | `instructor_lite` | 1.2.0 | 2026-02-01 | 3.5 万 | 131 | 5+ | - | - |
| **GenAI** | `genai` | 0.2.4 | 2025-08-12 | 2.6K | 26 | 9+ | ✓ | 不明 |
| **LlmComposer** | `llm_composer` | 0.14.2 | 2026-02-10 | 8K | - | 5+ | ✓ | ✓ |

#### 各库定位

- **LangChain**：最成熟的完整框架，47 万下载，13 个包依赖它。链式调用 + 工具 + Memory。
- **ReqLLM**：最现代的 LLM 客户端，45 个提供商 / 665+ 模型自动同步，Vercel AI SDK 风格 API，内建费用追踪。
- **Anthropix**：Anthropic 专用客户端，API 干净，支持 tool calling、流式、扩展思考、prompt 缓存、批量处理。
- **OpenaiEx**：OpenAI 专用，覆盖所有 API 端点（含 Responses API），28 万下载。
- **InstructorLite**：结构化输出提取，支持 Anthropic 原生 structured output（2026 年 1 月 GA）。
- **LlmComposer**：提供商路由 + 故障转移（先试 OpenAI，失败切 Gemini，指数退避）。

### 9.5 Jido 生态：现成的 Agent 框架（推荐方案）

经过深入代码分析，**Jido + jido_ai + ReqLLM 已经实现了我们讨论的所有 Agent 能力**。不需要从零构建。

#### 三层架构

```
┌─────────────────────────────────────────────────────┐
│  jido_ai（桥接层）                                    │
│  ToolAdapter / Executor / ReAct Strategy / Machine   │
├──────────────────────┬──────────────────────────────┤
│  jido（Agent 框架）   │  req_llm（LLM 客户端）        │
│  Agent / AgentServer │  generate_text / stream_text  │
│  Signal / Directive  │  45 提供商 / 665+ 模型        │
│  Strategy / Action   │  Tool / ToolCall / Response   │
└──────────────────────┴──────────────────────────────┘
```

- **ReqLLM** 只管调 LLM API，不知道 Agent 是啥
- **Jido** 只管 Agent 生命周期和状态机，不知道 LLM 是啥
- **jido_ai** 把两者粘起来

#### Agent 定义

Jido Agent 是**纯函数式的不可变 struct**，不是进程。GenServer 只是可选的运行时包装。

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "coding-agent",
    description: "编码助手",
    schema: [
      workspace: [type: :string, required: true],
      history: [type: {:list, :map}, default: []]
    ]
end

# Agent 核心操作是纯函数
{updated_agent, directives} = MyAgent.cmd(agent, SomeAction)
# agent 不可变，updated_agent 是新值
# directives 描述副作用（发信号、启动进程等），由 AgentServer 执行
```

#### Action = 工具模块

每个 Action 是独立模块，有 schema、description、run/2 回调：

```elixir
defmodule ReadFile do
  use Jido.Action,
    name: "read_file",
    description: "读取文件内容",
    schema: [
      path: [type: :string, required: true],
      offset: [type: :integer, default: 0],
      limit: [type: :integer, default: 2000]
    ]

  def run(params, _context) do
    content = File.read!(params.path)
    # 分页截断等逻辑
    {:ok, %{content: content, total_lines: count_lines(content)}}
  end
end
```

#### 关键粘合：Action ↔ LLM Tool Call

**ToolAdapter** 把 Jido Action 转成 ReqLLM Tool 定义（发给 LLM）：

```elixir
# jido_ai/tool_adapter.ex
def from_actions(actions) do
  Enum.map(actions, fn action_module ->
    ReqLLM.tool(
      name: action_module.name(),
      description: action_module.description(),
      parameter_schema: Jido.Action.Schema.to_json_schema(action_module)
    )
  end)
end
```

**Executor** 在 LLM 返回 tool_call 后，查找并执行对应的 Action：

```elixir
# jido_ai/executor.ex
def execute(tool_name, params, tools_map, context) do
  module = Map.fetch!(tools_map, tool_name)
  normalized = ActionTool.convert_params_using_schema(module, params)
  task = Task.async(fn -> Jido.Exec.run(module, normalized, context) end)
  case Task.yield(task, timeout) || Task.shutdown(task) do
    {:ok, {:ok, result}} -> format_result(result)
    nil -> {:error, "Tool execution timed out"}
  end
end
```

#### 信号驱动的 Agent Loop

不是传统的 while 循环，而是**状态机 + 信号**模式：

```
用户: "帮我重构这个函数"
    │
    ▼ Signal: react.input
AgentServer(GenServer)
    │
    ▼ 状态机: idle → awaiting_llm
    │ Directive: LLMStream → ReqLLM.stream_text(model, messages, tools: tools)
    │
    ▼ Signal: react.llm.response (含 tool_calls: [read_file, edit_file])
    │ 状态机: awaiting_llm → awaiting_tool
    │
    ▼ Directive: ToolExec → Executor.execute("read_file", %{path: "..."})
    │                     → Executor.execute("edit_file", %{path: "...", ...})
    │
    ▼ Signal: react.tool.result (工具结果)
    │ 状态机: awaiting_tool → awaiting_llm（带工具结果重新调 LLM）
    │
    ▼ Directive: LLMStream → 再次调 ReqLLM.stream_text()
    │
    ▼ Signal: react.llm.response (纯文本回答，无 tool_calls)
    │ 状态机: awaiting_llm → completed
    │
    ▼ 返回结果
```

状态机转换图：

```
                    ┌─────────────────────────────────────┐
                    │                                     │
                    ▼                                     │
    ┌───────┐  react.input  ┌──────────────┐             │
    │ idle  │──────────────>│ awaiting_llm │             │
    └───────┘               └──────┬───────┘             │
                                   │                     │
                        ┌──────────┴──────────┐          │
                        │                     │          │
                 有 tool_calls          纯文本回答        │
                        │                     │          │
                        ▼                     ▼          │
               ┌───────────────┐      ┌───────────┐     │
               │ awaiting_tool │      │ completed │     │
               └───────┬───────┘      └───────────┘     │
                       │                                 │
              所有工具执行完毕                              │
              且未超 max_iterations                        │
                       │                                 │
                       └─────────────────────────────────┘
```

#### OTP 进程树

```
Jido (Supervisor)
├── Task.Supervisor          # 异步工具执行，支持超时和中断
├── Registry                 # 按 ID 查找 Agent 进程
└── DynamicSupervisor        # 动态管理 Agent 进程
    ├── AgentServer (GenServer) - agent_1
    ├── AgentServer (GenServer) - agent_2
    └── ...
```

AgentServer 的 drain loop 处理 Directive 队列：

```elixir
# agent_server.ex
def handle_info(:drain, state) do
  case :queue.out(state.directive_queue) do
    {{:value, directive}, remaining} ->
      DirectiveExec.exec(directive, state.agent, state)
      send(self(), :drain)  # 继续处理下一个
      {:noreply, %{state | directive_queue: remaining}}
    {:empty, _} ->
      {:noreply, state}
  end
end
```

#### 与 Pi 实现的对照

| 能力 | Pi (TypeScript) | Jido (Elixir) |
|------|----------------|---------------|
| Agent 循环 | 双层 while 循环 | 状态机 + Signal 驱动 |
| 中断机制 | pendingMessages 数组 | GenServer.cast + 进程邮箱 |
| 工具执行 | 顺序 + AbortSignal | Task.async/yield/shutdown |
| 事件流 | EventEmitter subscribe | Phoenix.PubSub / GenStage |
| 多会话 | 文件锁 | DynamicSupervisor + Registry |
| 容错 | try/catch | Supervisor 自动重启 |
| 流式 LLM | 自建 SSE 解析 | ReqLLM 内建 Finch SSE |
| 多提供商 | 自建 18+ adapter | ReqLLM 45+ 提供商 |
| 上下文压缩 | 自建 LLM 摘要 | 需自行实现（Jido 未内建） |
| 工具数量 | 7 个精打细磨 | 需自行实现 Action 模块 |

#### 我们需要做的 vs 不需要做的

**不需要做的**（Jido + ReqLLM 已提供）：
- Agent 生命周期管理（GenServer/Supervisor/Registry）
- 信号路由和 Directive 执行
- LLM API 调用和流式解析（45 个提供商）
- 工具调用协议（Action → Tool 转换 → 执行 → 结果回传）
- ReAct 循环状态机
- 请求追踪（async/await 模式）

**需要自己做的**：
- 7 个 Action 模块（read/write/edit/bash/grep/find/ls），参考 Pi 的边界处理
- 上下文压缩（Jido 未内建，需自行实现 LLM 摘要逻辑）
- 截断系统（head/tail/line + UTF-8 边界）
- edit 的两层匹配（精确 → 模糊 + Unicode 规范化）
- bash 的滚动缓冲区和进程树管理
- LiveView 集成层（接 Signal 做实时 UI）

### 9.6 最终结论

**不需要从零构建 Agent 框架。**

直接使用 Jido 生态（`jido` + `jido_ai` + `req_llm`）作为基础：

```elixir
# mix.exs
defp deps do
  [
    {:jido, "~> 2.0.0-rc.4"},
    {:jido_ai, "~> x.x"},
    {:req_llm, "~> 1.5"},
    # ... 现有依赖
  ]
end
```

工作量从 ~7000 行（全部自建）缩减到 **~2000-2500 行**：

| 模块 | 行数估算 | 说明 |
|------|---------|------|
| 7 个 Action 模块 | ~1200 | read/write/edit/bash/grep/find/ls |
| 截断系统 | ~200 | head/tail/line + UTF-8 |
| 上下文压缩 | ~300 | LLM 摘要 + 切割点逻辑 |
| LiveView 集成 | ~400 | Signal → LiveView 事件 |
| 配置和胶水代码 | ~200 | Agent 定义、路由、初始化 |
| **合计** | **~2300** | 不含测试 |
| 测试 | ~1500 | |
| **总计** | **~3800** | 比全自建省一半 |

独立的 `tape` CLI (Go) 仍然可以后续单独做，作为存储/查询工具与 Elixir Agent 互补。
