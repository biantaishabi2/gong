defmodule Gong.SessionModelSyncTest do
  use ExUnit.Case, async: false

  alias Gong.ModelRegistry
  alias Gong.Session
  alias Gong.Settings

  setup do
    workspace = Path.join(System.tmp_dir!(), "gong-session-sync-#{System.unique_integer([:positive])}")
    File.mkdir_p!(workspace)
    settings_file = Path.join([workspace, ".gong", "settings.json"])
    old_settings_file = System.get_env("GONG_SETTINGS_FILE")
    System.put_env("GONG_SETTINGS_FILE", settings_file)

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
      if old_settings_file do
        System.put_env("GONG_SETTINGS_FILE", old_settings_file)
      else
        System.delete_env("GONG_SETTINGS_FILE")
      end

      Settings.cleanup()
      ModelRegistry.cleanup()
      File.rm_rf!(workspace)
    end)

    {:ok, workspace: workspace, session: session, settings_file: settings_file}
  end

  test "sync_model 在 settings 变更后更新 session metadata", %{workspace: workspace, session: session} do
    assert {:ok, %{changed: false}} = Session.sync_model(session)

    assert {:ok, %{short: "kimi"}} = Settings.set_model(workspace, "k2p5")
    assert {:ok, %{changed: true, model: "kimi"}} = Session.sync_model(session)

    assert {:ok, metadata} = Session.metadata(session)
    assert get_in(metadata, ["session", "model"]) == "kimi"
  end

  test "settings 写入非法模型时，sync_model 忽略变更并保持当前模型", %{
    settings_file: settings_file,
    session: session
  } do
    File.mkdir_p!(Path.dirname(settings_file))
    File.write!(settings_file, ~s({"model":"unknown-model"}))

    assert {:ok, %{changed: false, reason: :invalid, requested: "unknown-model"}} =
             Session.sync_model(session)

    assert {:ok, metadata} = Session.metadata(session)
    assert get_in(metadata, ["session", "model"]) == "minimax"
  end

  test "switch_model 直接切换当前会话模型", %{session: session} do
    assert {:ok, %{changed: true, model: "kimi"}} = Session.switch_model(session, "kimi")

    assert {:ok, metadata} = Session.metadata(session)
    assert get_in(metadata, ["session", "model"]) == "kimi"
  end

  test "switch_model 重复切换同模型返回 unchanged", %{session: session} do
    assert {:ok, %{changed: false, reason: :unchanged, model: "minimax"}} =
             Session.switch_model(session, "minimax")
  end
end
