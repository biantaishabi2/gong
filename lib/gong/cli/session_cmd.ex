defmodule Gong.CLI.SessionCmd do
  @moduledoc """
  会话持久化命令 — 列出/恢复/保存会话快照。

  快照存放在 `{tape_path}/sessions/{session_id}.json`。
  """

  @sessions_dir "sessions"

  @doc "列出所有已保存会话"
  @spec list_sessions(Path.t()) :: {:ok, [map()]}
  def list_sessions(workspace_path) do
    dir = sessions_dir(workspace_path)

    if File.dir?(dir) do
      sessions =
        dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn filename ->
          path = Path.join(dir, filename)

          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, data} -> data
                _ -> nil
              end

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1["saved_at"], :desc)

      {:ok, sessions}
    else
      {:ok, []}
    end
  end

  @doc "恢复指定会话"
  @spec restore_session(Path.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def restore_session(workspace_path, session_id) do
    path = session_file(workspace_path, session_id)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, snapshot} -> {:ok, snapshot}
          _ -> {:error, "not_found"}
        end

      {:error, _} ->
        {:error, "not_found"}
    end
  end

  @doc "保存会话快照"
  @spec save_session(Path.t(), String.t(), map()) :: :ok
  def save_session(workspace_path, session_id, snapshot) do
    dir = sessions_dir(workspace_path)
    File.mkdir_p!(dir)

    path = session_file(workspace_path, session_id)
    data = Map.put(snapshot, "saved_at", System.os_time(:millisecond))
    File.write!(path, Jason.encode!(data, pretty: true))
    :ok
  end

  defp sessions_dir(workspace_path), do: Path.join(workspace_path, @sessions_dir)
  defp session_file(workspace_path, session_id), do: Path.join(sessions_dir(workspace_path), "#{session_id}.json")
end
