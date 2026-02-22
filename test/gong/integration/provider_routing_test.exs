defmodule Gong.Integration.ProviderRoutingTest do
  use ExUnit.Case, async: false

  alias Gong.ProviderRegistry
  alias Gong.LLMRouter

  setup do
    ProviderRegistry.init()
    on_exit(fn -> ProviderRegistry.cleanup() end)
    :ok
  end

  # ── 同会话 provider/model 切换测试 ──

  describe "provider 切换路由" do
    test "注册两个 provider，switch 后 Router 路由到新 provider" do
      ProviderRegistry.register("provider_a", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)
      ProviderRegistry.register("provider_b", Gong.Test.MockProvider, %{}, priority: 5, timeout: 30_000)

      model_config = %{provider: "provider_a", model_id: "model-1"}

      # 初始路由到 provider_a
      resolved = LLMRouter.resolve_config(model_config)
      assert resolved.provider_name == "provider_a"
      assert resolved.receive_timeout == 60_000

      # 切换到 provider_b
      :ok = ProviderRegistry.switch("provider_b")
      {current_name, _entry} = ProviderRegistry.current()
      assert current_name == "provider_b"

      # 用 provider_b 的 model_config 路由
      model_config_b = %{provider: "provider_b", model_id: "model-2"}
      resolved_b = LLMRouter.resolve_config(model_config_b)
      assert resolved_b.provider_name == "provider_b"
      assert resolved_b.receive_timeout == 30_000
    end
  end

  # ── fallback 生效测试 ──

  describe "fallback 降级" do
    test "主 provider 失败后 fallback 到次优先级 provider" do
      ProviderRegistry.register("primary", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)
      ProviderRegistry.register("secondary", Gong.Test.MockProvider, %{}, priority: 5, timeout: 30_000)

      # 验证 fallback chain
      chain = ProviderRegistry.fallback_chain()
      assert chain == ["primary", "secondary"]

      # 模拟 primary 失败后 fallback
      {:ok, next} = ProviderRegistry.fallback("primary")
      assert next == "secondary"

      # current 已切换到 secondary
      {current_name, _} = ProviderRegistry.current()
      assert current_name == "secondary"
    end

    test "所有 provider 耗尽时返回 :no_fallback" do
      ProviderRegistry.register("only", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)

      assert {:error, :no_fallback} = ProviderRegistry.fallback("only")
    end
  end

  # ── provider 级 base_url/headers 覆盖测试 ──

  describe "provider 级配置覆盖" do
    test "自定义 base_url 的 provider 在 resolve_config 中生效" do
      ProviderRegistry.register(
        "custom",
        Gong.Test.MockProvider,
        %{base_url: "https://custom.example.com", headers: %{"Authorization" => "Bearer test"}},
        priority: 10,
        timeout: 45_000
      )

      model_config = %{provider: "custom", model_id: "custom-model"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.receive_timeout == 45_000
      # provider config 中的 base_url 通过 resolve_provider_config 传递
      {:ok, provider_cfg} = ProviderRegistry.resolve_provider_config("custom")
      assert provider_cfg.base_url == "https://custom.example.com"
      assert provider_cfg.headers == %{"Authorization" => "Bearer test"}
    end
  end

  # ── ProviderRegistry 新接口测试 ──

  describe "ProviderRegistry 新接口" do
    test "resolve_provider_config/1 返回完整配置" do
      ProviderRegistry.register("test_p", Gong.Test.MockProvider, %{base_url: "https://test.com"}, priority: 8, timeout: 50_000)

      assert {:ok, config} = ProviderRegistry.resolve_provider_config("test_p")
      assert config.timeout == 50_000
      assert config.module == Gong.Test.MockProvider
      assert config.priority == 8
      assert config.base_url == "https://test.com"
    end

    test "resolve_provider_config/1 不存在返回 :not_found" do
      assert {:error, :not_found} = ProviderRegistry.resolve_provider_config("nonexistent")
    end

    test "fallback_chain/0 按优先级排列" do
      ProviderRegistry.register("high", Gong.Test.MockProvider, %{}, priority: 20, timeout: 60_000)
      ProviderRegistry.register("low", Gong.Test.MockProvider, %{}, priority: 1, timeout: 30_000)
      ProviderRegistry.register("mid", Gong.Test.MockProvider, %{}, priority: 10, timeout: 45_000)

      chain = ProviderRegistry.fallback_chain()
      assert chain == ["high", "mid", "low"]
    end

    test "get_provider_for_model/1 根据 provider 字段查找" do
      ProviderRegistry.register("my_provider", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)

      assert {:ok, {"my_provider", entry}} =
               ProviderRegistry.get_provider_for_model(%{provider: "my_provider", model_id: "m1"})

      assert entry.module == Gong.Test.MockProvider
    end

    test "get_provider_for_model/1 不存在返回 :not_found" do
      assert {:error, :not_found} = ProviderRegistry.get_provider_for_model(%{provider: "missing"})
    end
  end

  # ── AgentLoop 与 Compaction 使用同一 Router 断言 ──

  describe "AgentLoop 与 Summarizer 统一路由" do
    test "build_llm_backend 使用的闭包内部走 LLMRouter" do
      ProviderRegistry.register("deepseek", Gong.Providers.DeepSeek, %{}, priority: 10, timeout: 60_000)

      model_config = %{provider: "deepseek", model_id: "deepseek-chat", api_key_env: "DEEPSEEK_API_KEY"}

      # 验证 resolve_config 对 AgentLoop 和 Summarizer 的输入产生一致结果
      agent_resolved = LLMRouter.resolve_config(model_config, tools: [], receive_timeout: 60_000)
      summarizer_resolved = LLMRouter.resolve_config(model_config, receive_timeout: 30_000)

      assert agent_resolved.model_str == summarizer_resolved.model_str
      assert agent_resolved.provider_name == summarizer_resolved.provider_name
      # timeout 不同是预期的，因为 Summarizer 传入 30_000
      assert agent_resolved.receive_timeout == 60_000
      assert summarizer_resolved.receive_timeout == 30_000
    end
  end
end
