defmodule Gong.Tape.Index do
  @moduledoc "Tape SQLite 索引层 — 元数据与全文搜索"

  @spec open(Path.t()) :: {:ok, Exqlite.Sqlite3.db()} | {:error, term()}
  def open(db_path) do
    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        :ok = setup_schema(conn)
        {:ok, conn}

      error ->
        error
    end
  end

  @spec close(Exqlite.Sqlite3.db()) :: :ok
  def close(conn) do
    Exqlite.Sqlite3.close(conn)
    :ok
  end

  @spec insert_anchor(Exqlite.Sqlite3.db(), integer(), String.t()) :: :ok | {:error, term()}
  def insert_anchor(conn, seq, name) do
    exec(conn, "INSERT OR IGNORE INTO anchors (seq, name) VALUES (?1, ?2)", [seq, name])
  end

  @spec anchor_count(Exqlite.Sqlite3.db()) :: integer()
  def anchor_count(conn) do
    [[count]] = query(conn, "SELECT COUNT(*) FROM anchors", [])
    count
  end

  @spec next_anchor_seq(Exqlite.Sqlite3.db()) :: integer()
  def next_anchor_seq(conn) do
    case query(conn, "SELECT MAX(seq) FROM anchors", []) do
      [[nil]] -> 1
      [[max]] -> max + 1
    end
  end

  @spec insert_entry(Exqlite.Sqlite3.db(), map()) :: :ok | {:error, term()}
  def insert_entry(conn, %{id: id, anchor: anchor, kind: kind, content: content, timestamp: ts} = entry) do
    metadata_json = entry |> Map.get(:metadata, %{}) |> Jason.encode!()

    exec(
      conn,
      "INSERT INTO entries (id, anchor, kind, content, timestamp, metadata) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
      [id, anchor, kind, content, ts, metadata_json]
    )
  end

  @spec entry_count(Exqlite.Sqlite3.db()) :: integer()
  def entry_count(conn) do
    [[count]] = query(conn, "SELECT COUNT(*) FROM entries", [])
    count
  end

  @spec entry_count_for_anchor(Exqlite.Sqlite3.db(), String.t()) :: integer()
  def entry_count_for_anchor(conn, anchor) do
    [[count]] = query(conn, "SELECT COUNT(*) FROM entries WHERE anchor = ?1", [anchor])
    count
  end

  @spec entries_between(Exqlite.Sqlite3.db(), String.t(), String.t()) :: [map()]
  def entries_between(conn, start_anchor, end_anchor) do
    # 获取 anchor 序号范围
    rows =
      query(
        conn,
        """
        SELECT e.id, e.anchor, e.kind, e.content, e.timestamp, e.metadata
        FROM entries e
        JOIN anchors a ON e.anchor = a.name
        WHERE a.seq >= (SELECT seq FROM anchors WHERE name = ?1)
          AND a.seq <= (SELECT seq FROM anchors WHERE name = ?2)
        ORDER BY e.timestamp ASC
        """,
        [start_anchor, end_anchor]
      )

    Enum.map(rows, &row_to_entry/1)
  end

  @spec search(Exqlite.Sqlite3.db(), String.t()) :: [map()]
  def search(conn, query_text) do
    rows =
      query(
        conn,
        "SELECT id, anchor, kind, content, timestamp, metadata FROM entries WHERE content LIKE ?1",
        ["%#{query_text}%"]
      )

    Enum.map(rows, &row_to_entry/1)
  end

  @spec all_entries(Exqlite.Sqlite3.db()) :: [map()]
  def all_entries(conn) do
    rows = query(conn, "SELECT id, anchor, kind, content, timestamp, metadata FROM entries ORDER BY timestamp ASC", [])
    Enum.map(rows, &row_to_entry/1)
  end

  @spec clear_entries(Exqlite.Sqlite3.db()) :: :ok
  def clear_entries(conn) do
    exec(conn, "DELETE FROM entries", [])
  end

  @spec clear_all(Exqlite.Sqlite3.db()) :: :ok
  def clear_all(conn) do
    exec(conn, "DELETE FROM entries", [])
    exec(conn, "DELETE FROM anchors", [])
  end

  # ── 内部实现 ──

  defp setup_schema(conn) do
    exec(conn, "PRAGMA journal_mode=WAL", [])

    exec(conn, """
    CREATE TABLE IF NOT EXISTS anchors (
      seq INTEGER PRIMARY KEY,
      name TEXT UNIQUE NOT NULL
    )
    """, [])

    exec(conn, """
    CREATE TABLE IF NOT EXISTS entries (
      id TEXT PRIMARY KEY,
      anchor TEXT NOT NULL,
      kind TEXT NOT NULL,
      content TEXT NOT NULL,
      timestamp INTEGER NOT NULL,
      metadata TEXT DEFAULT '{}'
    )
    """, [])

    exec(conn, "CREATE INDEX IF NOT EXISTS idx_entries_anchor ON entries(anchor)", [])
    :ok
  end

  defp exec(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    if params != [] do
      :ok = Exqlite.Sqlite3.bind(stmt, params)
    end

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        :done -> :ok
        {:row, _} -> drain_rows(conn, stmt) && :ok
        {:error, reason} -> {:error, reason}
      end

    release_stmt(conn, stmt)
    result
  end

  defp query(conn, sql, params) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    if params != [] do
      :ok = Exqlite.Sqlite3.bind(stmt, params)
    end

    rows = collect_rows(conn, stmt, [])
    release_stmt(conn, stmt)
    rows
  end

  defp collect_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> collect_rows(conn, stmt, acc ++ [row])
      :done -> acc
    end
  end

  defp drain_rows(conn, stmt) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, _} -> drain_rows(conn, stmt)
      :done -> true
    end
  end

  defp release_stmt(conn, stmt) do
    try do
      Exqlite.Sqlite3.release(conn, stmt)
    rescue
      _ -> :ok
    end
  end

  defp row_to_entry([id, anchor, kind, content, timestamp]) do
    %{id: id, anchor: anchor, kind: kind, content: content, timestamp: timestamp, metadata: %{}}
  end

  defp row_to_entry([id, anchor, kind, content, timestamp, metadata_json]) do
    metadata =
      case Jason.decode(metadata_json || "{}") do
        {:ok, map} when is_map(map) -> map
        _ -> %{}
      end

    %{id: id, anchor: anchor, kind: kind, content: content, timestamp: timestamp, metadata: metadata}
  end
end
