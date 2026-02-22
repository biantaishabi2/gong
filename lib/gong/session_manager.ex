defmodule Gong.SessionManager do
  @moduledoc """
  Session 生命周期管理入口。

  通过 DynamicSupervisor + Registry 管理 Session 进程，
  支持 CRUD 操作和分布式 RPC 调用。
  """

  alias Gong.Session

  require Logger

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
  按 external_session_key 查找或创建 Session。

  命中已存活的 session 则复用，否则创建新会话。
  """
  @spec get_or_create_session(String.t(), keyword()) :: {:ok, pid(), String.t()} | {:error, term()}
  def get_or_create_session(external_session_key, opts \\ []) when is_binary(external_session_key) do
    case find_by_external_key(external_session_key) do
      {:ok, session_id, pid} ->
        :telemetry.execute(
          [:gong, :session, :reuse_hit],
          %{system_time: System.system_time(:millisecond)},
          %{session_id: session_id, external_session_key: external_session_key}
        )

        Logger.info("Session 复用命中",
          session_id: session_id,
          external_session_key: external_session_key
        )

        {:ok, pid, session_id}

      :not_found ->
        opts = Keyword.put(opts, :external_session_key, external_session_key)
        result = create_session(opts)

        case result do
          {:ok, _pid, session_id} ->
            :telemetry.execute(
              [:gong, :session, :reuse_miss],
              %{system_time: System.system_time(:millisecond)},
              %{session_id: session_id, external_session_key: external_session_key}
            )

            Logger.info("Session 复用未命中，新建",
              session_id: session_id,
              external_session_key: external_session_key
            )

          _ ->
            :ok
        end

        result
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
  @spec close_session(String.t(), atom()) :: :ok | {:error, :not_found}
  def close_session(session_id, reason \\ :manual) do
    case get_session(session_id) do
      {:ok, pid} -> Session.close(pid, reason)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  当前活跃会话总数。
  """
  @spec session_count() :: non_neg_integer()
  def session_count do
    try do
      :ets.info(Gong.SessionIndex, :size) || 0
    rescue
      ArgumentError -> 0
    end
  end

  # 按 external_session_key 在 ETS 索引中查找存活的 session
  defp find_by_external_key(external_session_key) do
    try do
      # ETS 表结构: {session_id, external_session_key, created_at, last_active_at, pid}
      matches = :ets.match_object(Gong.SessionIndex, {:_, external_session_key, :_, :_, :_})

      case matches do
        [] ->
          :not_found

        entries ->
          # 找到第一个进程存活的条目
          Enum.find_value(entries, :not_found, fn {session_id, _key, _created, _active, pid} ->
            if Process.alive?(pid) do
              {:ok, session_id, pid}
            else
              # 清理残留条目
              :ets.delete(Gong.SessionIndex, session_id)
              nil
            end
          end)
      end
    rescue
      ArgumentError -> :not_found
    end
  end

  defp generate_session_id do
    "session_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
