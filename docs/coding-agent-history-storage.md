# Coding Agent 历史记录存储位置

本文档记录各种 AI Coding Agent 的历史记录/对话记录存储位置和格式。

## 总结对比

| 工具 | 存储路径 | 格式 | 结构 | 特点 |
|-----|---------|------|------|------|
| **Claude Code** | `~/.claude/history.jsonl` | **JSONL** 单一大文件 | 所有 session 在一个文件 | 仅用户输入，按行追加 |
| **Claude (项目级)** | `~/.claude/projects/<project-name>/` | **JSONL** 多文件 | 按 session ID 分文件 | 完整对话（user + assistant + tools） |
| **Codex** | `~/.codex/history.jsonl` | **JSONL** 单一大文件 | 所有 session 在一个文件 | 类似 Claude，仅用户输入 |
| **Kimi** | `~/.kimi/sessions/` + `~/.kimi/user-history/` | **JSONL** 多文件 | 每个 session 独立目录 | 用户输入 + AI 回复 |
| **OpenCode** | `~/.local/share/opencode/storage/` | **JSON** 分层目录 | session → message → part 三层 | 最完整，含 system prompt、skills |

---

## Claude Code

### 全局历史
```
~/.claude/history.jsonl
```
- **格式**: JSONL（每行一个 JSON 对象）
- **内容**: 仅用户输入
- **示例**:
```jsonl
{"display":"用中文重复你刚才的回答","timestamp":1771226889551,"project":"/home/wangbo/document/Cli","sessionId":"43261aa1-061c-46a2-b7b5-e16f2692c121"}
```

### 项目级历史
```
~/.claude/projects/<encoded-project-path>/
├── <session-id>.jsonl
└── memory/
```

**示例路径**:
- `~/.claude/projects/-home-wangbo-document-gong/`
- `~/.claude/projects/-home-wangbo-actions-runner-gong-1--work-gong-gong/`

**内容**: 完整对话记录（user message, assistant response, tool calls）

---

## Codex (OpenAI)

```
~/.codex/
├── history.jsonl          # 主要历史记录 (~3MB)
├── config.toml            # 配置文件
├── auth.json              # 认证信息
├── sessions/              # session 数据
└── ...
```

**格式**: JSONL，每行包含:
```jsonl
{"session_id":"0199ff6b-9c6a-7ce2-9f4d-95c1d1b49338","ts":1760926870,"text":"你好"}
```

---

## Kimi Code CLI

```
~/.kimi/
├── sessions/
│   └── <hash>/            # 每个 session 一个目录
├── user-history/
│   └── <hash>.jsonl       # 历史记录文件
├── kimi.json              # 工作目录和 last_session_id 映射
└── config.toml            # 配置
```

**格式**: JSONL，包含用户输入和 AI 回复

---

## OpenCode

最复杂的存储结构，分层设计：

```
~/.local/share/opencode/storage/
├── session/               # Session 元数据
│   └── <project_hash>/
│       └── ses_<id>.json
├── message/               # 消息列表
│   └── ses_<id>/
│       └── msg_<id>.json
├── part/                  # 消息实际内容
│   └── msg_<id>/
│       └── prt_<id>.json
├── session_diff/          # Session 差异
├── project/               # 项目信息
├── todo/                  # Todo 列表
└── ...
```

**额外文件**:
```
~/.local/state/opencode/
├── prompt-history.jsonl   # 简化的用户输入历史
├── kv.json               # 键值存储
└── model.json            # 模型配置
```

**特点**:
- 唯一使用普通 JSON（非 JSONL）
- 唯一包含完整的 system prompt 和 skill 内容
- 分层结构：Session → Message → Part

---

## 快速查找命令

```bash
# Claude 全局历史
grep "session-id" ~/.claude/history.jsonl

# Claude 项目历史
ls ~/.claude/projects/ | grep gong

# Codex 历史
head ~/.codex/history.jsonl

# Kimi 历史
ls ~/.kimi/user-history/

# OpenCode 历史
ls ~/.local/share/opencode/storage/session/
```

---

## 注意事项

1. **隐私**: 这些历史文件可能包含敏感信息（代码、密钥等）
2. **备份**: JSONL 文件可以按行增量备份
3. **迁移**: Claude/Codex/Kimi 都是 JSONL，易于迁移；OpenCode 结构复杂
4. **大小**: 长期使用后文件可能很大（Claude 的 history.jsonl 可达 8MB+）
