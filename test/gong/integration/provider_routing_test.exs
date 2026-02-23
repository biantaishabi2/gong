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

  # ── 三层 headers 合并集成测试 ──

  describe "三层 headers 合并" do
    test "provider + model + runtime 同时配置时 runtime 优先" do
      ProviderRegistry.register(
        "header_test",
        Gong.Test.MockProvider,
        %{headers: %{"Auth" => "pk", "X-Provider" => "pv"}},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{
        provider: "header_test",
        model_id: "test-model",
        headers: %{"Auth" => "mk", "X-Custom" => "cv"}
      }

      resolved = LLMRouter.resolve_config(model_config, headers: %{"X-Custom" => "rv", "X-New" => "nv"})

      assert resolved.headers == %{
               "Auth" => "mk",
               "X-Provider" => "pv",
               "X-Custom" => "rv",
               "X-New" => "nv"
             }
    end

    test "base_url runtime 覆盖 model" do
      ProviderRegistry.register("base_test", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)

      model_config = %{
        provider: "base_test",
        model_id: "test-model",
        base_url: "https://model.api.com"
      }

      resolved = LLMRouter.resolve_config(model_config, base_url: "http://localhost:8080")
      assert resolved.base_url == "http://localhost:8080"
    end

    test "deepseek 路由回归：默认路由在 headers 透传后行为不变" do
      ProviderRegistry.register("deepseek", Gong.Test.MockProvider, %{}, priority: 10, timeout: 60_000)

      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.model_str == "deepseek:deepseek-chat"
      assert resolved.headers == %{}
      assert resolved.provider_name == "deepseek"
      assert resolved.receive_timeout == 60_000
    end
  end

  # ── 协议型 provider 与 alias 解析测试 ──

  describe "协议型 provider 注册与 alias 解析" do
    test "register_compat 注册后 resolve_provider_config 返回正确 base_url" do
      ProviderRegistry.register_compat(
        :openai_compat,
        "deepseek",
        %{base_url: "https://api.deepseek.com", api_key_env: "DEEPSEEK_API_KEY"},
        priority: 10,
        timeout: 60_000
      )

      assert {:ok, config} = ProviderRegistry.resolve_provider_config("openai_compat:deepseek")
      assert config.base_url == "https://api.deepseek.com"
      assert config.module == Gong.Providers.OpenaiCompatProvider
      assert config.timeout == 60_000
    end

    test "通过旧名称 alias 查找返回 canonical provider 配置" do
      ProviderRegistry.register_compat(
        :openai_compat,
        "deepseek",
        %{base_url: "https://api.deepseek.com", api_key_env: "DEEPSEEK_API_KEY"},
=======
      model_config = %{
        provider: "hp_test",
        model_id: "test-model",
        header_profile: :opencode,
        headers: %{"X-Model" => "mv"}
      }

      resolved = LLMRouter.resolve_config(model_config)

      # profile 基底
      assert resolved.headers["User-Agent"] == "OpenCode/1.0"
      assert resolved.headers["X-Client-Name"] == "opencode"
      # provider 覆盖 profile 的 Accept
      assert resolved.headers["Accept"] == "text/plain"
      # provider 独有头保留
      assert resolved.headers["X-Provider"] == "pv"
      # model 独有头保留
      assert resolved.headers["X-Model"] == "mv"
    end

    test "profile + provider + model + runtime 四层合并" do
      ProviderRegistry.register(
        "hp_full",
        Gong.Test.MockProvider,
        %{headers: %{"X-Provider" => "pv"}},
>>>>>>> origin/integration/main
        priority: 10,
        timeout: 60_000
      )

<<<<<<< HEAD
      # 通过 alias "deepseek" 解析到 "openai_compat:deepseek"
      assert ProviderRegistry.resolve_alias("deepseek") == "openai_compat:deepseek"

      # resolve_provider_config 通过 alias 透明解析
      assert {:ok, config} = ProviderRegistry.resolve_provider_config("deepseek")
      assert config.base_url == "https://api.deepseek.com"
      assert config.module == Gong.Providers.OpenaiCompatProvider
    end

    test "get_provider_for_model 通过 alias 解析旧 provider 名称" do
      ProviderRegistry.register_compat(
        :openai_compat,
        "deepseek",
        %{base_url: "https://api.deepseek.com", api_key_env: "DEEPSEEK_API_KEY"},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}

      assert {:ok, {"openai_compat:deepseek", entry}} =
               ProviderRegistry.get_provider_for_model(model_config)

      assert entry.module == Gong.Providers.OpenaiCompatProvider
      assert entry.config.base_url == "https://api.deepseek.com"
    end

    test "fallback chain 中协议 provider 优先级排序正确" do
      ProviderRegistry.register_compat(
        :openai_compat,
        "deepseek",
        %{base_url: "https://api.deepseek.com", api_key_env: "DEEPSEEK_API_KEY"},
        priority: 10,
        timeout: 60_000
      )

      ProviderRegistry.register_compat(
        :anthropic_compat,
        "anthropic",
        %{base_url: "https://api.anthropic.com", api_key_env: "ANTHROPIC_API_KEY"},
        priority: 5,
        timeout: 30_000
      )

      chain = ProviderRegistry.fallback_chain()
      assert chain == ["openai_compat:deepseek", "anthropic_compat:anthropic"]
    end

    test "switch 通过 alias 名称切换 provider" do
      ProviderRegistry.register_compat(
        :openai_compat,
        "deepseek",
        %{base_url: "https://api.deepseek.com", api_key_env: "DEEPSEEK_API_KEY"},
        priority: 10,
        timeout: 60_000
      )

      ProviderRegistry.register_compat(
        :anthropic_compat,
        "anthropic",
        %{base_url: "https://api.anthropic.com", api_key_env: "ANTHROPIC_API_KEY"},
        priority: 5,
        timeout: 30_000
      )

      # 通过 alias 切换
      :ok = ProviderRegistry.switch("anthropic")
      {current_name, _} = ProviderRegistry.current()
      assert current_name == "anthropic_compat:anthropic"
    end

    test "无匹配 alias 时透传原名" do
      assert ProviderRegistry.resolve_alias("unknown") == "unknown"
    end
  end

  # ── header_profile 端到端合并测试 ──

  describe "header_profile 三层合并" do
    test "profile + provider + model 三层合并优先级正确" do
      ProviderRegistry.register(
        "hp_test",
        Gong.Test.MockProvider,
        %{headers: %{"X-Provider" => "pv", "Accept" => "text/plain"}},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{
        provider: "hp_test",
        model_id: "test-model",
        header_profile: :opencode,
        headers: %{"X-Model" => "mv"}
      }

      resolved = LLMRouter.resolve_config(model_config)

      # profile 基底
      assert resolved.headers["User-Agent"] == "OpenCode/1.0"
      assert resolved.headers["X-Client-Name"] == "opencode"
      # provider 覆盖 profile 的 Accept
      assert resolved.headers["Accept"] == "text/plain"
      # provider 独有头保留
      assert resolved.headers["X-Provider"] == "pv"
      # model 独有头保留
      assert resolved.headers["X-Model"] == "mv"
    end

    test "profile + provider + model + runtime 四层合并" do
      ProviderRegistry.register(
        "hp_full",
        Gong.Test.MockProvider,
        %{headers: %{"X-Provider" => "pv"}},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{
        provider: "hp_full",
        model_id: "test-model",
        header_profile: :opencode,
        headers: %{"Accept" => "text/html"}
      }

      resolved = LLMRouter.resolve_config(model_config, headers: %{"User-Agent" => "RuntimeUA"})

      # runtime 覆盖 profile 的 User-Agent
      assert resolved.headers["User-Agent"] == "RuntimeUA"
      # model 覆盖 profile 的 Accept
      assert resolved.headers["Accept"] == "text/html"
      # profile 独有头保留
      assert resolved.headers["X-Client-Name"] == "opencode"
      # provider 独有头保留
      assert resolved.headers["X-Provider"] == "pv"
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
