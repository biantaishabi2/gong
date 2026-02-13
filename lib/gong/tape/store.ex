defmodule Gong.Tape.Store do
  @moduledoc """
  Tape 存储层 — 文件夹 + SQLite 索引。

  内容按 anchor（阶段）分目录存放为 JSONL 文件，
  元数据和索引存入 SQLite 数据库，查询走索引定位后读文件。

  ## 存储结构

      workspace/
      ├── anchors/
      │   ├── 001_session-start/
      │   │   ├── messages.jsonl
      │   │   └── tool_calls.jsonl
      │   ├── 002_phase-1/
      │   │   └── ...
      │   └── ...
      └── index.db
  """

  alias Gong.Tape.{Entry, Index, FileStore}

  @type t :: %__MODULE__{
          workspace_path: Path.t(),
          db_conn: reference() | nil
        }

  defstruct [:workspace_path, :db_conn]

  @default_anchor "session-start"

  # ── 初始化 ──

  @doc "初始化工作区存储"
  @spec init(Path.t()) :: {:ok, t()} | {:error, term()}
  def init(workspace_path) do
    anchors_path = Path.join(workspace_path, "anchors")
    db_path = Path.join(workspace_path, "index.db")

    File.mkdir_p!(anchors_path)

    # 打开 SQLite
    case Index.open(db_path) do
      {:ok, conn} ->
        store = %__MODULE__{workspace_path: workspace_path, db_conn: conn}

        # 幂等：只在 anchor_count=0 时创建默认 anchor
        if Index.anchor_count(conn) == 0 do
          dir_name = "001_#{@default_anchor}"
          File.mkdir_p!(Path.join(anchors_path, dir_name))
          Index.insert_anchor(conn, 1, @default_anchor)
        end

        {:ok, store}

      error ->
        error
    end
  end

  # ── 追加 ──

  @doc "追加条目到指定 anchor"
  @spec append(t(), String.t(), map()) :: {:ok, t()} | {:error, term()}
  def append(%__MODULE__{} = store, anchor_name, %{kind: kind, content: content} = params) do
    metadata = Map.get(params, :metadata, %{})

    # 验证 anchor 存在
    case find_anchor_dir(store, anchor_name) do
      {:ok, dir_path} ->
        entry = Entry.new(anchor_name, kind, content, metadata)

        # 双写：文件 + 数据库
        FileStore.append(dir_path, entry)
        Index.insert_entry(store.db_conn, Map.from_struct(entry))

        {:ok, store}

      :error ->
        {:error, "anchor not found"}
    end
  end

  # ── Handoff ──

  @doc "创建新 anchor（阶段切换）"
  @spec handoff(t(), String.t()) :: {:ok, String.t(), t()} | {:error, term()}
  def handoff(%__MODULE__{} = store, name) do
    # 检查重复名称
    case find_anchor_dir(store, name) do
      {:ok, _} ->
        {:error, "anchor already exists"}

      :error ->
        seq = Index.next_anchor_seq(store.db_conn)
        dir_name = "#{String.pad_leading(Integer.to_string(seq), 3, "0")}_#{name}"
        dir_path = Path.join([store.workspace_path, "anchors", dir_name])

        File.mkdir_p!(dir_path)
        Index.insert_anchor(store.db_conn, seq, name)

        {:ok, dir_name, store}
    end
  end

  # ── 查询 ──

  @doc "按 anchor 范围查询条目"
  @spec between_anchors(t(), String.t(), String.t()) :: {:ok, [map()]}
  def between_anchors(%__MODULE__{} = store, start_anchor, end_anchor) do
    entries = Index.entries_between(store.db_conn, start_anchor, end_anchor)
    {:ok, entries}
  end

  @doc "全文搜索"
  @spec search(t(), String.t()) :: {:ok, [map()]}
  def search(%__MODULE__{} = store, query_text) do
    entries = Index.search(store.db_conn, query_text)
    {:ok, entries}
  end

  # ── Fork / Merge ──

  @doc "创建隔离 fork 工作区"
  @spec fork(t()) :: {:ok, t()} | {:error, term()}
  def fork(%__MODULE__{} = store) do
    fork_path = store.workspace_path <> "_fork_#{System.unique_integer([:positive])}"

    # 复制目录结构（不复制 index.db，重建）
    File.mkdir_p!(fork_path)
    anchors_src = Path.join(store.workspace_path, "anchors")
    anchors_dst = Path.join(fork_path, "anchors")

    case System.cmd("cp", ["-r", anchors_src, anchors_dst], stderr_to_stdout: true) do
      {_, 0} ->
        # 在 fork 中初始化新 DB
        case init(fork_path) do
          {:ok, fork_store} ->
            # 从文件重建索引
            rebuild_index_internal(fork_store)
            {:ok, fork_store}

          error ->
            File.rm_rf!(fork_path)
            error
        end

      {err, _} ->
        {:error, "fork copy failed: #{err}"}
    end
  end

  @doc "合并 fork 数据回主工作区"
  @spec merge(t(), t()) :: {:ok, t()} | {:error, term()}
  def merge(%__MODULE__{} = parent, %__MODULE__{} = fork_store) do
    fork_anchors_path = Path.join(fork_store.workspace_path, "anchors")

    try do
      # 读取 fork 中所有条目
      fork_dirs = FileStore.list_anchor_dirs(fork_anchors_path)

      for dir_name <- fork_dirs do
        {_seq, anchor_name} = FileStore.parse_anchor_dir(dir_name)
        dir_path = Path.join(fork_anchors_path, dir_name)
        entries = FileStore.read_all(dir_path)

        # 确保 anchor 在父工作区存在
        case find_anchor_dir(parent, anchor_name) do
          {:ok, parent_dir} ->
            # 获取父工作区已有 entry id
            parent_entries = FileStore.read_all(parent_dir)
            parent_ids = MapSet.new(parent_entries, & &1.id)

            # 只追加 fork 中新增的条目
            new_entries = Enum.reject(entries, fn e -> MapSet.member?(parent_ids, e.id) end)

            for entry <- new_entries do
              FileStore.append(parent_dir, entry)
              Index.insert_entry(parent.db_conn, Map.from_struct(entry))
            end

          :error ->
            # fork 中有新 anchor，创建之
            {:ok, _dir_name, _store} = handoff(parent, anchor_name)
            {:ok, new_dir} = find_anchor_dir(parent, anchor_name)

            for entry <- entries do
              FileStore.append(new_dir, entry)
              Index.insert_entry(parent.db_conn, Map.from_struct(entry))
            end
        end
      end

      # 清理 fork 临时目录
      cleanup_fork(fork_store)
      {:ok, parent}
    rescue
      e ->
        cleanup_fork(fork_store)
        {:error, "merge failed: #{Exception.message(e)}"}
    end
  end

  # ── 索引重建 ──

  @doc "从 JSONL 文件重建 SQLite 索引"
  @spec rebuild_index(t()) :: {:ok, t()} | {:error, term()}
  def rebuild_index(%__MODULE__{} = store) do
    db_path = Path.join(store.workspace_path, "index.db")

    # 关闭旧连接（如果有）
    if store.db_conn, do: Index.close(store.db_conn)

    # 删除旧 DB，重新打开
    File.rm(db_path)

    case Index.open(db_path) do
      {:ok, conn} ->
        new_store = %{store | db_conn: conn}
        rebuild_index_internal(new_store)
        {:ok, new_store}

      error ->
        error
    end
  end

  # ── 辅助查询 ──

  @doc "获取条目总数"
  @spec entry_count(t()) :: integer()
  def entry_count(%__MODULE__{} = store) do
    Index.entry_count(store.db_conn)
  end

  @doc "获取锚点数量"
  @spec anchor_count(t()) :: integer()
  def anchor_count(%__MODULE__{} = store) do
    Index.anchor_count(store.db_conn)
  end

  @doc "关闭 DB 连接"
  @spec close(t()) :: :ok
  def close(%__MODULE__{db_conn: nil}), do: :ok

  def close(%__MODULE__{db_conn: conn}) do
    Index.close(conn)
  end

  # ── 分支操作 ──

  @doc "从指定 anchor 创建分支，返回新 anchor 名"
  @spec branch_from(t(), String.t()) :: {:ok, String.t(), t()} | {:error, term()}
  def branch_from(%__MODULE__{} = store, anchor_name) do
    parent_seq = Index.anchor_seq(store.db_conn, anchor_name)

    if parent_seq == nil do
      {:error, "anchor not found: #{anchor_name}"}
    else
      branch_name = "#{anchor_name}_branch_#{System.unique_integer([:positive])}"
      seq = Index.next_anchor_seq(store.db_conn)
      dir_name = "#{String.pad_leading(Integer.to_string(seq), 3, "0")}_#{branch_name}"
      dir_path = Path.join([store.workspace_path, "anchors", dir_name])

      File.mkdir_p!(dir_path)
      Index.insert_anchor(store.db_conn, seq, branch_name, parent_seq)

      {:ok, branch_name, store}
    end
  end

  @doc "切换到指定分支的叶节点"
  @spec navigate(t(), String.t()) :: {:ok, t()} | {:error, term()}
  def navigate(%__MODULE__{} = store, anchor_name) do
    seq = Index.anchor_seq(store.db_conn, anchor_name)

    if seq == nil do
      {:error, "anchor not found: #{anchor_name}"}
    else
      {:ok, store}
    end
  end

  @doc "列出指定 anchor 的直接子分支"
  @spec branches(t(), String.t()) :: [String.t()]
  def branches(%__MODULE__{} = store, anchor_name) do
    seq = Index.anchor_seq(store.db_conn, anchor_name)

    if seq == nil do
      []
    else
      Index.child_anchors(store.db_conn, seq)
      |> Enum.map(& &1.name)
    end
  end

  @doc "从 anchor 回溯到 root 构建上下文路径"
  @spec build_context_path(t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def build_context_path(%__MODULE__{} = store, anchor_name) do
    seq = Index.anchor_seq(store.db_conn, anchor_name)

    if seq == nil do
      {:error, "anchor not found: #{anchor_name}"}
    else
      # 获取祖先路径上的所有 anchor
      path = Index.ancestor_path(store.db_conn, seq)
      anchor_names = Enum.map(path, & &1.name)

      # 收集每个 anchor 的条目
      entries =
        Enum.flat_map(anchor_names, fn name ->
          case find_anchor_dir(store, name) do
            {:ok, dir_path} ->
              FileStore.read_all(dir_path)
              |> Enum.map(&Map.from_struct/1)
            :error ->
              []
          end
        end)
        |> Enum.sort_by(& &1.timestamp)

      {:ok, entries}
    end
  end

  @doc "生成分支摘要"
  @spec generate_branch_summary(t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def generate_branch_summary(%__MODULE__{} = store, anchor_name) do
    case build_context_path(store, anchor_name) do
      {:ok, entries} ->
        # 简单摘要：提取关键操作描述
        summary =
          entries
          |> Enum.map(fn e -> "[#{e.kind}] #{String.slice(to_string(e.content), 0, 50)}" end)
          |> Enum.join(" → ")

        {:ok, summary}

      error ->
        error
    end
  end

  # ── 私有辅助 ──

  defp find_anchor_dir(%__MODULE__{workspace_path: ws}, anchor_name) do
    anchors_path = Path.join(ws, "anchors")

    case FileStore.list_anchor_dirs(anchors_path) do
      dirs ->
        found =
          Enum.find(dirs, fn dir ->
            {_seq, name} = FileStore.parse_anchor_dir(dir)
            name == anchor_name
          end)

        if found do
          {:ok, Path.join(anchors_path, found)}
        else
          :error
        end
    end
  end

  defp rebuild_index_internal(%__MODULE__{} = store) do
    anchors_path = Path.join(store.workspace_path, "anchors")
    dirs = FileStore.list_anchor_dirs(anchors_path)

    for dir_name <- dirs do
      {seq, anchor_name} = FileStore.parse_anchor_dir(dir_name)
      Index.insert_anchor(store.db_conn, seq, anchor_name)

      dir_path = Path.join(anchors_path, dir_name)
      entries = FileStore.read_all(dir_path)

      for entry <- entries do
        Index.insert_entry(store.db_conn, Map.from_struct(entry))
      end
    end
  end

  defp cleanup_fork(%__MODULE__{} = fork_store) do
    if fork_store.db_conn, do: Index.close(fork_store.db_conn)
    File.rm_rf(fork_store.workspace_path)
  end
end
