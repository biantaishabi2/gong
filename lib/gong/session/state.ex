defmodule Gong.Session.State do
  @moduledoc """
  Session 进程状态。

  注意：Session GenServer 实际使用 plain map 作为状态，
  此模块仅作为类型定义参考。
  """

  @type close_reason ::
          :manual
          | :ttl_idle_expired
          | :ttl_absolute_expired
          | :lru_evicted
          | :fatal_error

  @type runner_result ::
          {:ok, String.t()}
          | {:ok, String.t(), [Gong.Session.Events.t()]}
          | {:error, term()}
          | {:error, term(), [Gong.Session.Events.t()]}

  @type runner :: (String.t(), t(), keyword() -> runner_result())

  @type t :: %__MODULE__{
          runner: runner(),
          session_manager: term(),
          settings_manager: term(),
          steering_messages: [String.t()],
          follow_up_messages: [String.t()],
          pending_next_turn: [String.t()],
          is_streaming: boolean(),
          current_turn: non_neg_integer(),
          compaction_opts: keyword(),
          retry_opts: keyword(),
          extension_runner: term(),
          event_listeners: [{reference(), (Gong.Session.Events.t() -> any())}],
          base_system_prompt: String.t(),
          scoped_models: [String.t()],
          cwd: String.t(),
          model: String.t() | nil,
          history: [map()],
          inflight_call: GenServer.from() | nil,
          inflight_task_ref: reference() | nil,
          external_session_key: String.t() | nil,
          created_at: integer() | nil,
          last_active_at: integer() | nil,
          close_reason: close_reason() | nil
        }

  defstruct [
    runner: nil,
    session_manager: nil,
    settings_manager: nil,
    steering_messages: [],
    follow_up_messages: [],
    pending_next_turn: [],
    is_streaming: false,
    current_turn: 0,
    compaction_opts: [],
    retry_opts: [],
    extension_runner: nil,
    event_listeners: [],
    base_system_prompt: "",
    scoped_models: [],
    cwd: "",
    model: nil,
    history: [],
    inflight_call: nil,
    inflight_task_ref: nil,
    external_session_key: nil,
    created_at: nil,
    last_active_at: nil,
    close_reason: nil
  ]
end
