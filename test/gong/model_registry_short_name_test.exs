defmodule Gong.ModelRegistryShortNameTest do
  use ExUnit.Case, async: false

  alias Gong.ModelRegistry

  setup do
    ModelRegistry.init()

    ModelRegistry.register(:kimi, %{
      provider: "kimi",
      model_id: "k2p5",
      api_key_env: "KIMI_API_KEY"
    })

    ModelRegistry.register(:minimax, %{
      provider: "minimax",
      model_id: "MiniMax-M2.5",
      api_key_env: "MINIMAX_API_KEY"
    })

    ModelRegistry.register(:glm, %{
      provider: "glm",
      model_id: "glm-4.7",
      api_key_env: "GLM_API_KEY"
    })

    on_exit(fn -> ModelRegistry.cleanup() end)
    :ok
  end

  test "短名 minimax 命中注册模型" do
    assert {:ok, config} = ModelRegistry.lookup_by_string("minimax")
    assert config.provider == "minimax"
    assert config.model_id == "MiniMax-M2.5"
  end

  test "短名 kimi-2.5 映射为 kimi 注册模型" do
    assert {:ok, config} = ModelRegistry.lookup_by_string("kimi-2.5")
    assert config.provider == "kimi"
    assert config.model_id == "k2p5"
  end

  test "短名 k2p5 映射为 kimi 注册模型" do
    assert {:ok, config} = ModelRegistry.lookup_by_string("k2p5")
    assert config.provider == "kimi"
    assert config.model_id == "k2p5"
  end

  test "短名 deepseek 返回 deepseek 默认模型" do
    assert {:ok, config} = ModelRegistry.lookup_by_string("deepseek")
    assert config.provider == "deepseek"
    assert config.model_id == "deepseek-chat"
  end

  test "完整 provider:model 仍可解析" do
    assert {:ok, config} = ModelRegistry.lookup_by_string("minimax:MiniMax-M2.5")
    assert config.provider == "minimax"
    assert config.model_id == "MiniMax-M2.5"
  end

  test "未知短名返回错误" do
    assert {:error, :unknown_provider} = ModelRegistry.lookup_by_string("not-exists")
  end

  test "resolve_registered_model 仅命中已注册模型，不做兜底构造" do
    assert {:ok, resolved} = ModelRegistry.resolve_registered_model("k2p5")
    assert resolved.short == "kimi"
    assert resolved.model == "kimi:k2p5"

    assert {:ok, resolved2} = ModelRegistry.resolve_registered_model("minimax:MiniMax-M2.5")
    assert resolved2.short == "minimax"
    assert resolved2.model == "minimax:MiniMax-M2.5"

    assert {:error, :unknown_provider} = ModelRegistry.resolve_registered_model("unknown:model")
  end

  test "available_models 返回短名与完整名映射" do
    available = ModelRegistry.available_models()
    shorts = Enum.map(available, & &1.short)
    models = Enum.map(available, & &1.model)

    assert "kimi" in shorts
    assert "minimax" in shorts
    assert "glm" in shorts
    assert "kimi:k2p5" in models
  end
end
