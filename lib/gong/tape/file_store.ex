defmodule Gong.Tape.FileStore do
  @moduledoc "Tape JSONL 文件存储层 — 按 anchor + kind 分文件"

  alias Gong.Tape.Entry

  @doc "获取 anchor 目录路径"
  @spec anchor_dir(Path.t(), String.t()) :: Path.t()
  def anchor_dir(anchors_path, anchor_dir_name) do
    Path.join(anchors_path, anchor_dir_name)
  end

  @doc "获取 kind 对应的 JSONL 文件名"
  @spec jsonl_filename(String.t()) :: String.t()
  def jsonl_filename(kind) do
    case kind do
      "message" -> "messages.jsonl"
      "tool_call" -> "tool_calls.jsonl"
      _ -> "#{kind}s.jsonl"
    end
  end

  @doc "追加条目到 JSONL 文件"
  @spec append(Path.t(), Entry.t()) :: :ok
  def append(dir_path, %Entry{} = entry) do
    file = Path.join(dir_path, jsonl_filename(entry.kind))
    line = Entry.to_json(entry) <> "\n"
    File.write!(file, line, [:append])
    :ok
  end

  @doc "从 anchor 目录读取所有条目（跳过坏行）"
  @spec read_all(Path.t()) :: [Entry.t()]
  def read_all(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.flat_map(fn file ->
          read_jsonl(Path.join(dir_path, file))
        end)
        |> Enum.sort_by(& &1.timestamp)

      {:error, _} ->
        []
    end
  end

  @doc "从单个 JSONL 文件读取条目（跳过 malformed 行）"
  @spec read_jsonl(Path.t()) :: [Entry.t()]
  def read_jsonl(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.flat_map(fn line ->
          case Entry.from_json(line) do
            {:ok, entry} -> [entry]
            :error -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  @doc "列出 anchors 目录下所有 anchor 目录名（已排序）"
  @spec list_anchor_dirs(Path.t()) :: [String.t()]
  def list_anchor_dirs(anchors_path) do
    case File.ls(anchors_path) do
      {:ok, dirs} ->
        dirs
        |> Enum.filter(fn d -> File.dir?(Path.join(anchors_path, d)) end)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc "从 anchor 目录名提取序号和名称"
  @spec parse_anchor_dir(String.t()) :: {integer(), String.t()}
  def parse_anchor_dir(dir_name) do
    case Regex.run(~r/^(\d+)_(.+)$/, dir_name) do
      [_, seq_str, name] -> {String.to_integer(seq_str), name}
      _ -> {0, dir_name}
    end
  end
end
