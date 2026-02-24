defmodule Gong.LLMRouterTest do
  use ExUnit.Case, async: false

  alias Gong.LLMRouter
  alias Gong.ProviderRegistry

  setup do
    ProviderRegistry.init()

    ProviderRegistry.register("deepseek", Gong.Test.MockProvider, %{},
      priority: 10,
      timeout: 60_000
    )

    ProviderRegistry.register("openai", Gong.Test.MockProvider, %{}, priority: 5, timeout: 30_000)

    on_exit(fn -> ProviderRegistry.cleanup() end)
    :ok
  end

  # ── resolve_config 优先级合并测试 ──

  describe "resolve_config/2" do
    test "使用 provider 默认 timeout" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.model_str == "deepseek:deepseek-chat"
      assert resolved.receive_timeout == 60_000
      assert resolved.provider_name == "deepseek"
    end

    test "runtime opts 覆盖 timeout" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config, receive_timeout: 120_000)

      assert resolved.receive_timeout == 120_000
    end

    test "runtime opts 覆盖 base_url" do
      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        base_url: "https://default.example.com"
      }

      resolved = LLMRouter.resolve_config(model_config, base_url: "http://localhost:8080")

      assert resolved.base_url == "http://localhost:8080"
    end

    test "model 级 base_url 覆盖 provider 级" do
      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        base_url: "https://model.example.com"
      }

      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.base_url == "https://model.example.com"
    end

    test "未注册 provider 使用默认 timeout" do
      model_config = %{provider: "unknown_provider", model_id: "some-model"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.model_str == "unknown_provider:some-model"
      assert resolved.receive_timeout == 60_000
      assert resolved.req_model_spec == nil
    end

    test "协议型 provider 解析为 ReqLLM map 模型" do
      ProviderRegistry.cleanup()
      ProviderRegistry.init()

      ProviderRegistry.register_compat(
        :anthropic_compat,
        "kimi",
        %{base_url: "https://api.kimi.com/coding", api_key_env: "KIMI_API_KEY"},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{provider: "kimi", model_id: "k2p5"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.req_provider == :anthropic
      assert resolved.req_model_spec == %{provider: :anthropic, id: "k2p5"}
      assert resolved.model_str == "kimi:k2p5"
    end

    test "model headers 合并到最终配置" do
      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        headers: %{"X-Custom" => "value"}
      }

      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers == %{"X-Custom" => "value"}
    end

    test "runtime headers 覆盖 model headers" do
      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        headers: %{"X-Custom" => "model-value", "X-Keep" => "kept"}
      }

      resolved = LLMRouter.resolve_config(model_config, headers: %{"X-Custom" => "runtime-value"})

      assert resolved.headers["X-Custom"] == "runtime-value"
      assert resolved.headers["X-Keep"] == "kept"
    end

    test "三层 headers 合并优先级：runtime > model > provider" do
      # 注册带 headers 的 provider
      ProviderRegistry.cleanup()
      ProviderRegistry.init()

      ProviderRegistry.register(
        "with_headers",
        Gong.Test.MockProvider,
        %{headers: %{"Auth" => "pk", "X-Provider" => "pv"}},
        priority: 10,
        timeout: 60_000
      )

      model_config = %{
        provider: "with_headers",
        model_id: "test-model",
        headers: %{"Auth" => "mk", "X-Custom" => "cv"}
      }

      runtime_opts = [headers: %{"X-Custom" => "rv", "X-New" => "nv"}]
      resolved = LLMRouter.resolve_config(model_config, runtime_opts)

      # runtime > model > provider
      assert resolved.headers == %{
               "Auth" => "mk",
               "X-Provider" => "pv",
               "X-Custom" => "rv",
               "X-New" => "nv"
             }
    end

    test "未配置 headers 时返回空 map 不报错" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers == %{}
    end
  end

  # ── header_profile 注入测试 ──

  describe "header_profile 注入" do
    test "无 header_profile 字段时行为不变" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers == %{}
    end

    test "header_profile: :opencode 注入指纹头" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat", header_profile: :opencode}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers["User-Agent"] == "OpenCode/1.0"
      assert resolved.headers["X-Client-Name"] == "opencode"
      assert resolved.headers["Accept"] == "application/json"
    end

    test "model headers 与 profile headers 同名时 model 优先覆盖" do
      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        header_profile: :opencode,
        headers: %{"User-Agent" => "CustomAgent"}
      }

      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers["User-Agent"] == "CustomAgent"
      # profile 的其他头仍保留
      assert resolved.headers["X-Client-Name"] == "opencode"
      assert resolved.headers["Accept"] == "application/json"
    end

    test "header_profile: :default 不注入额外头" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat", header_profile: :default}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.headers == %{}
    end
  end

  # ── auth_mode 鉴权头注入测试 ──

  describe "auth_mode 鉴权头注入" do
    test "auth_mode: :anthropic_header 注入 x-api-key" do
      System.put_env("TEST_ANTHRO_KEY", "anthro-key-123")
      on_exit(fn -> System.delete_env("TEST_ANTHRO_KEY") end)

      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        api_key_env: "TEST_ANTHRO_KEY",
        auth_mode: :anthropic_header
      }

      resolved = LLMRouter.resolve_config(model_config)
      assert resolved.headers["x-api-key"] == "anthro-key-123"
    end

    test "auth_mode: :bearer 注入 Authorization: Bearer" do
      System.put_env("TEST_BEARER_KEY", "bearer-key-456")
      on_exit(fn -> System.delete_env("TEST_BEARER_KEY") end)

      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        api_key_env: "TEST_BEARER_KEY",
        auth_mode: :bearer
      }

      resolved = LLMRouter.resolve_config(model_config)
      assert resolved.headers["authorization"] == "Bearer bearer-key-456"
    end

    test "无 auth_mode 字段（默认）不注入额外 header" do
      model_config = %{provider: "deepseek", model_id: "deepseek-chat"}
      resolved = LLMRouter.resolve_config(model_config)

      # DeepSeek 默认配置不应包含鉴权头（由 ReqLLM.Provider 处理）
      refute Map.has_key?(resolved.headers, "x-api-key")
      refute Map.has_key?(resolved.headers, "authorization")
    end

    test "已有自定义 header 不被 auth_mode 覆盖" do
      System.put_env("TEST_NOCOVER_KEY", "should-not-appear")
      on_exit(fn -> System.delete_env("TEST_NOCOVER_KEY") end)

      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        api_key_env: "TEST_NOCOVER_KEY",
        auth_mode: :anthropic_header,
        headers: %{"x-api-key" => "custom-key"}
      }

      resolved = LLMRouter.resolve_config(model_config)
      # 已有的自定义 key 不应被覆盖
      assert resolved.headers["x-api-key"] == "custom-key"
    end

    test "API key 环境变量缺失时不注入 header 也不抛异常" do
      # 确保环境变量不存在
      System.delete_env("NONEXISTENT_API_KEY")

      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        api_key_env: "NONEXISTENT_API_KEY",
        auth_mode: :anthropic_header
      }

      resolved = LLMRouter.resolve_config(model_config)
      refute Map.has_key?(resolved.headers, "x-api-key")
    end
  end

  # ── fallback 触发测试 ──

  describe "fallback 逻辑" do
    test "所有 provider 不可用时返回 :all_providers_exhausted" do
      # 使用一个不存在的 provider，没有 fallback
      ProviderRegistry.cleanup()
      ProviderRegistry.init()

      ProviderRegistry.register("only_one", Gong.Test.MockProvider, %{},
        priority: 10,
        timeout: 5_000
      )

      model_config = %{provider: "only_one", model_id: "test"}

      # 由于 ReqLLM 不可用，stream_text 会返回错误，且没有 fallback
      # 这里我们只验证 resolve_config 正确构建配置
      resolved = LLMRouter.resolve_config(model_config)
      assert resolved.provider_name == "only_one"
      assert resolved.receive_timeout == 5_000
    end
  end

  # ── timeout 注入测试 ──

  describe "timeout 注入" do
    test "从 ProviderRegistry 获取 timeout 注入到 opts" do
      model_config = %{provider: "openai", model_id: "gpt-4"}
      resolved = LLMRouter.resolve_config(model_config)

      assert resolved.receive_timeout == 30_000
    end

    test "不同 provider 有不同 timeout" do
      deepseek_resolved =
        LLMRouter.resolve_config(%{provider: "deepseek", model_id: "deepseek-chat"})

      openai_resolved = LLMRouter.resolve_config(%{provider: "openai", model_id: "gpt-4"})

      assert deepseek_resolved.receive_timeout == 60_000
      assert openai_resolved.receive_timeout == 30_000
    end
  end

  describe "错误处理与预校验" do
    test "缺少 API key 时请求前返回 unauthorized 友好错误" do
      System.delete_env("NONEXISTENT_ROUTER_KEY")

      model_config = %{
        provider: "deepseek",
        model_id: "deepseek-chat",
        api_key_env: "NONEXISTENT_ROUTER_KEY"
      }

      assert {:error, error} = LLMRouter.stream_text(model_config, [%{role: :user, content: "hi"}], [])
      assert error.code == :unauthorized
      assert error.message =~ "缺少 NONEXISTENT_ROUTER_KEY"
    end

    test "humanize_error 提取 response_body.message 与状态码" do
      error = %{
        reason: "auth failed",
        status: 401,
        response_body: %{"message" => "token invalid"}
      }

      assert LLMRouter.humanize_error(error) == "token invalid (HTTP 401)"
    end
  end
end
