defmodule Gong.SessionModelSyncTest do
  use ExUnit.Case, async: false

  alias Gong.ModelRegistry
  alias Gong.Session
  alias Gong.Settings

  setup do
    workspace = Path.join(System.tmp_dir!(), "gong-session-sync-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)

    ModelRegistry.init()

    ModelRegistry.register(:minimax, %{
      provider: "minimax",
      model_id: "MiniMax-M2.5",
      api_key_env: "MINIMAX_API_KEY"
    })

    ModelRegistry.register(:kimi, %{
      provider: "kimi",
      model_id: "k2p5",
      api_key_env: "KIMI_API_KEY"
    })

    Settings.cleanup()
    Settings.init(workspace)
    {:ok, _} = Settings.set_model(workspace, "minimax")

    {:ok, session} =
      Session.start_link(
        session_id: "session-model-sync",
        model: "minimax",
        workspace: workspace,
        model_sync: true
      )

    on_exit(fn ->
      if Process.alive?(session), do: Session.close(session)
      Settings.cleanup()
      ModelRegistry.cleanup()
      File.rm_rf!(workspace)
    end)

    {:ok, workspace: workspace, session: session}
  end

  test "sync_model 在 settings 变更后更新 session metadata", %{workspace: workspace, session: session} do
    assert {:ok, %{changed: false}} = Session.sync_model(session)

    assert {:ok, %{short: "kimi"}} = Settings.set_model(workspace, "k2p5")
    assert {:ok, %{changed: true, model: "kimi"}} = Session.sync_model(session)

    assert {:ok, metadata} = Session.metadata(session)
    assert get_in(metadata, ["session", "model"]) == "kimi"
  end

  test "settings 写入非法模型时，sync_model 忽略变更并保持当前模型", %{
    workspace: workspace,
    session: session
  } do
    settings_file = Path.join([workspace, ".gong", "settings.json"])
    File.mkdir_p!(Path.dirname(settings_file))
    File.write!(settings_file, ~s({"model":"unknown-model"}))

    assert {:ok, %{changed: false, reason: :invalid, requested: "unknown-model"}} =
             Session.sync_model(session)

    assert {:ok, metadata} = Session.metadata(session)
    assert get_in(metadata, ["session", "model"]) == "minimax"
  end
end
