# Tape 存储层重新设计：独立 CLI 工具 + 文件夹 + 数据库索引

## 背景

当前 Bub 的 Tape 存储采用单个 JSONL 文件，所有条目（消息、工具调用、锚点等）追加写入同一个文件。这个方案实现简单，但存在明显的局限性：

- 文件会无限膨胀，需要额外的 archive 机制来缓解
- 查询依赖全量扫描，`search` 和 `between_anchors` 都要遍历每一行做 `json.loads`
- 历史越长，性能和可读性都越差
- 人工调试不友好，无法直观看到会话的阶段划分

## 核心思路

**索引和内容分离**——文件存内容，数据库存元数据和索引。查询走数据库定位，再去对应文件读完整内容。

这是成熟系统的常见模式：

- Git：对象存文件，引用和索引用单独结构管理
- 邮件客户端：邮件存文件，用 SQLite 做索引和搜索
- Elasticsearch：倒排索引与原始文档分开存储

## 存储结构

```
~/.bub/workspace-xxx/
├── anchors/                          # 按锚点（阶段）分目录存储内容
│   ├── 001_session-start/
│   │   ├── messages.jsonl            # 该阶段的对话消息
│   │   └── tool_calls.jsonl          # 该阶段的工具调用和结果
│   ├── 002_phase-1/
│   │   ├── messages.jsonl
│   │   └── tool_calls.jsonl
│   └── ...
├── index.db                          # SQLite 数据库，存元数据和索引
└── config.json                       # 工作区配置
```

### 文件层

- 按 anchor 分目录，每个阶段的内容独立存放
- 目录名带序号前缀，保证文件系统层面的顺序
- 同一阶段内可以按 kind 进一步分文件（messages、tool_calls 等）
- 每个文件保持 JSONL 格式，保留追加写入的简单性

### 数据库层（SQLite）

```sql
CREATE TABLE entries (
    id          INTEGER PRIMARY KEY,
    kind        TEXT NOT NULL,           -- message / tool_call / tool_result / anchor / event
    anchor_name TEXT NOT NULL,           -- 所属锚点/阶段名称
    anchor_seq  INTEGER NOT NULL,        -- 锚点序号
    file_path   TEXT NOT NULL,           -- 对应的文件相对路径
    line_offset INTEGER,                 -- 在文件中的行号，用于精确定位
    created_at  TEXT NOT NULL,           -- ISO 8601 时间戳
    summary     TEXT                     -- 可选的摘要/关键词，用于搜索
);

CREATE INDEX idx_entries_kind ON entries(kind);
CREATE INDEX idx_entries_anchor ON entries(anchor_name);
CREATE INDEX idx_entries_created ON entries(created_at);
CREATE INDEX idx_entries_summary ON entries(summary);
```

## 核心操作对比

### 查询：按锚点范围

**现有方案（全量扫描）：**

```python
def between_anchors(self, start, end):
    all_entries = self.read_entries()  # 读取全部条目
    # 遍历找到 start 和 end 的位置，再截取中间部分
```

**新方案（数据库索引）：**

```sql
SELECT * FROM entries
WHERE anchor_seq BETWEEN
    (SELECT anchor_seq FROM entries WHERE kind='anchor' AND anchor_name=?)
    AND
    (SELECT anchor_seq FROM entries WHERE kind='anchor' AND anchor_name=?)
ORDER BY id;
```

数据库定位后，再按 file_path 去读对应文件的具体内容。

### 查询：全文搜索

**现有方案：**

```python
def search(self, query):
    for entry in self.read_entries():          # 遍历每一条
        payload_text = json.dumps(entry.payload)  # 序列化
        if query.lower() in payload_text.lower(): # 字符串匹配
            results.append(entry)
```

**新方案：**

```sql
-- 先从索引定位
SELECT id, file_path, line_offset FROM entries
WHERE summary LIKE '%' || ? || '%';

-- 如果需要更强的全文搜索，可以启用 SQLite FTS5
CREATE VIRTUAL TABLE entries_fts USING fts5(summary, content=entries, content_rowid=id);
SELECT * FROM entries_fts WHERE entries_fts MATCH ?;
```

### 写入

```python
def append(self, anchor_name, entry):
    # 1. 写文件（追加到对应锚点目录下的 JSONL）
    file_path = self._anchor_file(anchor_name, entry.kind)
    with open(file_path, "a") as f:
        f.write(json.dumps(entry.payload) + "\n")

    # 2. 写索引（在 SQLite 事务中插入元数据）
    with self._db:
        self._db.execute(
            "INSERT INTO entries (kind, anchor_name, anchor_seq, file_path, line_offset, created_at, summary) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (entry.kind, anchor_name, seq, file_path, offset, now, summary)
        )
```

用 SQLite 事务保证文件和索引的一致性。

### Fork / Merge

- **fork**：在数据库中标记分支起始点（一个 savepoint），同时创建临时目录存放分支内容
- **merge**：将临时目录的文件追加到主目录，数据库中的分支记录合并到主表
- **失败回滚**：删除临时目录，数据库 rollback 到 savepoint

### Handoff（创建新锚点）

```python
def handoff(self, name, state=None):
    next_seq = self._next_anchor_seq()
    dir_name = f"{next_seq:03d}_{name}"
    os.makedirs(self._workspace / "anchors" / dir_name)

    with self._db:
        self._db.execute(
            "INSERT INTO entries (kind, anchor_name, anchor_seq, ...) VALUES ('anchor', ?, ?, ...)",
            (name, next_seq, ...)
        )
```

创建新目录 + 数据库记录，后续条目自动写入新目录。

## 优势总结

| 维度 | 现有方案（单 JSONL） | 新方案（文件夹 + SQLite） |
|------|----------------------|--------------------------|
| 查询性能 | O(n) 全量扫描 | O(log n) 索引查找 |
| 文件大小 | 无限膨胀 | 按阶段自然分割 |
| 人工可读性 | 需要工具解析 | 打开文件夹直接看 |
| 全文搜索 | 遍历 + 字符串匹配 | SQLite FTS5 |
| archive 需求 | 必须，否则文件过大 | 不需要，老阶段天然独立 |
| 跨阶段查询 | 全量读取后过滤 | SQL 范围查询 |
| 实现复杂度 | ~200 行 | ~400-500 行 |
| 一致性保证 | 仅文件级 append | SQLite 事务 + 文件双写 |

## 实现代价

- 代码量大约翻倍（200 行 -> 400-500 行）
- 需要维护数据库 schema 和迁移
- 写入时需要双写（文件 + 数据库），用 SQLite 事务保证一致性
- 引入 SQLite 依赖（Python 标准库自带，无额外安装）

这些都是成熟的工程问题，不存在技术风险。对于一个想在真实工程中长期使用的系统来说，这个投入是值得的。

## 产品形态：独立 CLI 工具

Tape 系统应该做成一个**独立的命令行工具**，而不是嵌入到某个项目中的库。

### 定位

这个工具的本质是**开发者基础设施**，跟 git 一个性质——你在终端里写代码，随时需要查会话、切阶段、搜历史。它不属于任何一个项目，而是跨项目、跨语言使用的。嵌入成库会把自己绑死在特定的语言生态里。

### CLI 命令设计

```bash
tape init                                    # 在当前目录初始化工作区
tape log                                     # 查看当前阶段的条目
tape log --kind tool_call                    # 只看工具调用
tape anchors                                 # 列出所有阶段
tape show phase-1                            # 查看某个阶段的完整内容
tape search "error"                          # 全文搜索（走 SQLite FTS）
tape search "error" --kind message           # 搜索 + 按类型过滤
tape handoff phase-2 --summary "xxx"         # 创建新锚点，进入下一阶段
tape append --kind message --anchor phase-2  # 追加条目
tape reset                                   # 重置当前磁带
tape reset --archive                         # 归档后重置
tape info                                    # 查看工作区状态（条目数、阶段数等）
```

### 零工具也能用

因为底层是文件夹结构，用户不装这个工具也能直接操作：

```bash
ls ~/.tape/workspace-xxx/anchors/            # 看有哪些阶段
cat ~/.tape/workspace-xxx/anchors/001_session-start/messages.jsonl  # 看某阶段的消息
```

CLI 只是让操作更方便，而不是唯一的访问方式。这是单 JSONL 文件做不到的。

### 与 Agent 框架的集成

CLI 工具本身不绑定任何 LLM 或 Agent 框架。Agent 框架通过两种方式集成：

1. **子进程调用** —— Agent 框架调用 `tape append ...`、`tape search ...` 等命令，通过 stdout/stderr 获取结果
2. **直接读写文件** —— 因为存储格式是公开透明的（文件夹 + JSONL + SQLite），任何语言都可以直接读写，不需要经过 CLI

Agent 框架负责自己的 LLM 调用和上下文拼装，tape 只负责存储和查询。职责分离，互不绑定。

## 语言选择：Go

选 Go 的理由：

- **单二进制分发** —— `go build` 出来一个可执行文件，不需要用户装任何运行时。跟 git 的分发体验一致
- **启动零延迟** —— 编译型语言，没有解释器初始化开销。CLI 工具对启动速度敏感，Python 在这里天然吃亏
- **SQLite 支持成熟** —— `mattn/go-sqlite3`（CGO）或 `modernc.org/sqlite`（纯 Go），两个方案都经过大规模生产验证
- **文件操作原生** —— `os`、`filepath`、`io` 标准库覆盖所有需求
- **交叉编译简单** —— `GOOS=linux GOARCH=amd64 go build` 就能出各平台的二进制，方便 CI/CD 分发

不选其他语言的原因：

- **Python** —— 启动慢，分发需要用户装 Python 和依赖，不适合做独立 CLI 工具
- **Rust** —— 性能更好但开发效率低，对这个项目来说过度工程
- **TypeScript** —— 需要 Node/Bun/Deno 运行时，分发不如单二进制干净
- **Elixir** —— 启动 BEAM VM 比 Python 还慢，CLI 场景不合适

## 项目结构（Go）

```
tape/
├── cmd/
│   └── tape/
│       └── main.go              # CLI 入口
├── internal/
│   ├── store/
│   │   ├── filestore.go         # 文件夹层：按 anchor 分目录读写 JSONL
│   │   ├── indexdb.go           # SQLite 索引层：元数据写入和查询
│   │   └── store.go             # 统一 Store 接口，协调文件和索引
│   ├── tape/
│   │   ├── entry.go             # TapeEntry 数据结构
│   │   ├── anchor.go            # Anchor / Handoff 逻辑
│   │   └── query.go             # 查询构建器（between_anchors 等）
│   └── workspace/
│       └── workspace.go         # 工作区初始化和路径解析
├── go.mod
└── go.sum
```
