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

  @type t :: %__MODULE__{}

  defstruct [:workspace_path, :db_conn]

  @doc "初始化工作区存储"
  @spec init(Path.t()) :: {:ok, t()} | {:error, term()}
  def init(workspace_path) do
    # TODO: 创建目录结构，初始化 SQLite
    {:ok, %__MODULE__{workspace_path: workspace_path}}
  end

  @doc "追加条目到指定 anchor"
  @spec append(t(), String.t(), map()) :: :ok | {:error, term()}
  def append(_store, _anchor_name, _entry) do
    # TODO: 双写文件 + 数据库
    :ok
  end

  @doc "创建新 anchor（阶段切换）"
  @spec handoff(t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def handoff(_store, name, _state \\ %{}) do
    # TODO: 创建新目录 + 数据库记录
    {:ok, "001_#{name}"}
  end

  @doc "按 anchor 范围查询条目"
  @spec between_anchors(t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def between_anchors(_store, _start, _end) do
    # TODO: SQL 范围查询 + 文件读取
    {:ok, []}
  end

  @doc "全文搜索"
  @spec search(t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def search(_store, _query) do
    # TODO: SQLite FTS5 搜索
    {:ok, []}
  end
end
