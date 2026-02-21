defmodule Gong.SessionManager do
  @moduledoc """
  Session 生命周期管理入口。

  通过 DynamicSupervisor + Registry 管理 Session 进程，
  支持 CRUD 操作和分布式 RPC 调用。
  """

  alias Gong.Session

  @doc """
  创建新 Session，由 DynamicSupervisor 监管并注册到 Registry。

  返回 `{:ok, pid, session_id}` 或 `{:error, reason}`。
  """
  @spec create_session(keyword()) :: {:ok, pid(), String.t()} | {:error, term()}
  def create_session(opts \\ []) do
    session_id = Keyword.get(opts, :session_id, generate_session_id())

    # 先检查 Registry，避免 start_link 内部 normalize_error 丢失结构化错误
    case Registry.lookup(Gong.SessionRegistry, session_id) do
      [{pid, _}] ->
        {:error, {:already_exists, pid, session_id}}

      [] ->
        opts = Keyword.put(opts, :session_id, session_id)

        child_spec = %{
          id: session_id,
          start: {Session, :start_supervised, [opts]},
          restart: :temporary
        }

        case DynamicSupervisor.start_child(Gong.SessionSupervisor, child_spec) do
          {:ok, pid} ->
            {:ok, pid, session_id}

          {:error, {:already_started, pid}} ->
            {:error, {:already_exists, pid, session_id}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  通过 session_id 查找 Session 进程。
  """
  @spec get_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_session(session_id) do
    case Registry.lookup(Gong.SessionRegistry, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  列出所有活跃 Session 的 ID。
  """
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    Registry.select(Gong.SessionRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  关闭指定 Session。
  """
  @spec close_session(String.t()) :: :ok | {:error, :not_found}
  def close_session(session_id) do
    case get_session(session_id) do
      {:ok, pid} -> Session.close(pid)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp generate_session_id do
    "session_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
