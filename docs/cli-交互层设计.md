# CLI 交互层设计

## 现状

`Gong.CLI` 当前只有两个命令：

```
bin/gong doctor [--cwd <path>]   # 运行时健康检查
bin/gong help                     # 帮助信息
```

Session API 已经完整（`prompt/2`、`subscribe/2`、`submit_command/3`、`history/1`、`restore/2`），但没有交互式消费者把它串起来。

---

## 目标

补一个薄壳，让 `bin/gong` 能直接跟 Agent 对话，验证 Session 全链路。

不做重型 TUI 框架，保持最小可用。

---

## 命令设计

### 新增命令

```
bin/gong chat [--cwd <path>] [--model <model>]
    交互式对话。启动 Session，进入 REPL 循环。

bin/gong run <prompt> [--cwd <path>] [--model <model>]
    单次执行。提交 prompt，输出结果，退出。

bin/gong session list [--cwd <path>]
    列出本地已保存的会话。

bin/gong session restore <session_id> [--cwd <path>]
    恢复一个历史会话并进入交互模式。
```

### 保留命令

```
bin/gong doctor [--cwd <path>]   # 不变
bin/gong help                     # 扩展帮助文本
```

---

## chat 命令流程

这是核心命令。流程如下：

```
用户输入
    ↓
CLI.main(["chat"])
    ↓
1. 创建 Session
   Session.start_link(llm_backend: LiveLLM.backend(), cwd: cwd)
    ↓
2. 订阅事件流
   Session.subscribe(session_pid, self())
    ↓
3. 进入 REPL 循环
   loop:
     prompt = IO.gets("> ")
     ├── "/exit"  → Session.close(pid), 退出
     ├── "/history" → 打印 Session.history(pid)
     ├── "/model <name>" → 切换模型
     ├── "/save" → 保存当前会话到 Tape
     └── 普通文本 → Session.prompt(pid, prompt)
                      ↓
                   接收事件流并渲染:
                     message.delta → IO.write(content)  # 流式输出
                     tool.start → 打印工具调用信息
                     tool.end → 打印工具结果摘要
                     lifecycle.completed → 换行，回到 prompt
                     error.* → 打印错误
```

### 事件渲染规则

```
message.start    → (无输出，标记开始)
message.delta    → IO.write(payload.content)   # 不换行，流式追加
message.end      → IO.write("\n")              # 换行

tool.start       → IO.puts("🔧 #{tool_name}(#{简化参数})")
tool.delta       → (静默，工具执行中)
tool.end         → IO.puts("  → #{截断结果, max 200 字符}")

lifecycle.completed → IO.puts("")              # 空行分隔

error.stream     → IO.puts(:stderr, "[ERROR] #{message}")
error.runtime    → IO.puts(:stderr, "[ERROR] #{message}")
```

---

## run 命令流程

单次执行，适合脚本调用和管道串接：

```
bin/gong run "在当前目录创建一个 hello.py"
```

流程：

```
1. 创建 Session（同 chat）
2. 订阅事件流
3. Session.prompt(pid, prompt)
4. 收集所有 message.delta 拼接为完整回复
5. 等待 lifecycle.completed
6. 输出完整回复到 stdout
7. 退出（exit code 0 成功 / 1 失败）
```

支持管道：

```bash
echo "解释这段代码" | bin/gong run --stdin
cat error.log | bin/gong run "分析这个错误日志"
```

---

## session 子命令

### session list

```
$ bin/gong session list
ID                                   | 创建时间            | 轮次 | 最后消息
─────────────────────────────────────────────────────────────────────
a1b2c3d4-...                         | 2026-02-20 14:30   | 12   | 把 hello.py 改成中文
e5f6g7h8-...                         | 2026-02-19 09:15   | 3    | 写一个斐波那契脚本
```

从 Tape 存储读取，用 SQLite Index 查询。

### session restore

```
$ bin/gong session restore a1b2c3d4
恢复会话 a1b2c3d4（12 轮对话）
> _
```

调用 `Session.restore/2` 恢复历史，进入 chat 循环。

---

## 实现层次

```
lib/gong/cli.ex              # 现有，扩展 parse_command 和 execute
lib/gong/cli/chat.ex         # 新增：REPL 循环 + 事件渲染
lib/gong/cli/run.ex          # 新增：单次执行
lib/gong/cli/session_cmd.ex  # 新增：session list/restore
lib/gong/cli/renderer.ex     # 新增：事件→终端输出 格式化
```

### cli.ex 改动

在 `parse_command` 中增加匹配：

```elixir
defp parse_command(["chat" | _rest], opts), do: {:ok, %{command: :chat, opts: opts}}
defp parse_command(["run" | rest], opts), do: {:ok, %{command: :run, prompt: Enum.join(rest, " "), opts: opts}}
defp parse_command(["session", "list"], opts), do: {:ok, %{command: :session_list, opts: opts}}
defp parse_command(["session", "restore", id | _], opts), do: {:ok, %{command: :session_restore, session_id: id, opts: opts}}
```

在 `execute` 中增加分发：

```elixir
defp execute(%{command: :chat, opts: opts}, runtime, run_opts) do
  cwd = resolve_cwd(opts, run_opts)
  Gong.CLI.Chat.start(cwd, opts)
end
```

### chat.ex 核心结构

```elixir
defmodule Gong.CLI.Chat do
  def start(cwd, opts) do
    model = opts[:model] || "deepseek:deepseek-chat"
    {:ok, session} = start_session(cwd, model)
    Session.subscribe(session, self())
    IO.puts("Gong Agent 就绪（#{model}）")
    IO.puts("输入 /exit 退出，/help 查看命令\n")
    loop(session)
  end

  defp loop(session) do
    prompt = IO.gets("> ") |> String.trim()
    case prompt do
      "/exit" -> Session.close(session)
      "/help" -> print_help(); loop(session)
      "/history" -> print_history(session); loop(session)
      "" -> loop(session)
      text ->
        Session.prompt(session, text)
        wait_completion(session)
        loop(session)
    end
  end

  defp wait_completion(session) do
    receive do
      {:session_event, %{type: "lifecycle.completed"}} -> :ok
      {:session_event, event} ->
        Gong.CLI.Renderer.render(event)
        wait_completion(session)
    after
      120_000 -> IO.puts(:stderr, "[TIMEOUT] Agent 响应超时")
    end
  end
end
```

### renderer.ex 核心结构

```elixir
defmodule Gong.CLI.Renderer do
  def render(%{type: "message.delta", payload: %{content: content}}) do
    IO.write(content)
  end

  def render(%{type: "message.end"}) do
    IO.write("\n")
  end

  def render(%{type: "tool.start", payload: payload}) do
    IO.puts("\n🔧 #{payload.name}(#{truncate(inspect(payload.arguments), 80)})")
  end

  def render(%{type: "tool.end", payload: payload}) do
    IO.puts("  → #{truncate(payload.result, 200)}")
  end

  def render(%{type: "error." <> _, payload: payload}) do
    IO.puts(:stderr, "[ERROR] #{payload.message}")
  end

  def render(_event), do: :ok

  defp truncate(text, max) when byte_size(text) > max do
    String.slice(text, 0, max) <> "..."
  end
  defp truncate(text, _max), do: text
end
```

---

## REPL 斜杠命令

| 命令 | 功能 |
|------|------|
| `/exit` | 关闭会话，退出 |
| `/help` | 显示可用命令 |
| `/history` | 显示对话历史摘要 |
| `/model <name>` | 切换 LLM 模型 |
| `/save` | 手动保存会话到 Tape |
| `/clear` | 清空当前会话上下文 |
| `/cost` | 显示本次会话 token 用量和费用 |

---

## 不做的事情

- **不做 TUI 框架** — 不用 Ratatouille/Owl 等，纯 IO.gets + IO.write
- **不做语法高亮** — 后续可以加，第一版不需要
- **不做多窗口/分屏** — 保持单流输出
- **不做 Web UI** — 那是 Gateway 项目的事
- **不做渠道适配** — 飞书/Slack 消息格式转换是 Gateway 项目的事

---

## 与 Gateway 项目的边界

```
CLI（本文档）:
  人 ──stdin/stdout──→ Gong Session
  场景：开发调试、本地使用、脚本集成

Gateway（独立项目）:
  飞书/Slack ──webhook──→ Gateway ──Session API──→ Gong Session
  场景：团队协作、生产部署、多渠道接入
```

两者都是 Session 的消费者，用同一套 API。CLI 是最薄的消费者，Gateway 是带路由和渠道适配的消费者。

---

## 实施步骤

1. **Renderer** — 事件→终端输出格式化（最简单，可独立测试）
2. **Chat** — REPL 循环 + 事件渲染（依赖 Renderer）
3. **Run** — 单次执行（复用 Renderer，简化版 Chat）
4. **Session Cmd** — list/restore（依赖 Tape 存储）
5. **CLI 入口扩展** — parse_command + execute 增加新命令

每步做完都可以实际跑一遍验证。
