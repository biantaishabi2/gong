defmodule Gong.SettingsTest do
  use ExUnit.Case, async: false

  alias Gong.ModelRegistry
  alias Gong.Settings

  setup do
    workspace = Path.join(System.tmp_dir!(), "gong-settings-#{System.unique_integer([:positive])}")
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

    on_exit(fn ->
      if old_settings_file do
        System.put_env("GONG_SETTINGS_FILE", old_settings_file)
      else
        System.delete_env("GONG_SETTINGS_FILE")
      end

      Settings.cleanup()
      ModelRegistry.cleanup()
      File.rm_rf!(workspace)
    end)

    {:ok, workspace: workspace, settings_file: settings_file}
  end

  test "set_model 原子写 settings.json 并更新 ETS", %{workspace: workspace, settings_file: settings_file} do
    assert {:ok, %{short: "kimi", model: "kimi:k2p5"}} = Settings.set_model(workspace, "k2p5")
    assert Settings.get_model() == "kimi"

    assert File.exists?(settings_file)
    refute File.exists?(settings_file <> ".tmp")

    {:ok, content} = File.read(settings_file)
    {:ok, settings_map} = Jason.decode(content)
    assert settings_map["model"] == "kimi"
  end

  test "set_model 遇到未知模型返回错误，不修改当前模型", %{workspace: workspace} do
    assert {:ok, %{short: "minimax", model: "minimax:MiniMax-M2.5"}} =
             Settings.set_model(workspace, "minimax")

    assert {:error, :unknown_provider} = Settings.set_model(workspace, "not-exists")
    assert Settings.get_model() == "minimax"
  end
end
