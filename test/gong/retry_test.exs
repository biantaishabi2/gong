defmodule Gong.RetryTest do
  use ExUnit.Case, async: true

  # 从 BDD 管线迁移的 Retry 模块单元测试
  # 覆盖错误分类、指数退避、重试策略

  describe "classify_error/1" do
    test "429 分类为 transient" do
      assert Gong.Retry.classify_error("HTTP 429 Too Many Requests") == :transient
    end

    test "rate limit 分类为 transient" do
      assert Gong.Retry.classify_error("429 rate limit") == :transient
    end

    test "context overflow 分类为 context_overflow" do
      assert Gong.Retry.classify_error("prompt is too long for the context window") ==
               :context_overflow
    end

    test "token exceeds context window 分类为 context_overflow" do
      assert Gong.Retry.classify_error("token count exceeds context window") == :context_overflow
    end

    test "ECONNREFUSED 分类为 transient" do
      assert Gong.Retry.classify_error("connect ECONNREFUSED 127.0.0.1:443") == :transient
    end

    test "timeout 分类为 transient" do
      assert Gong.Retry.classify_error("request timeout after 30s") == :transient
    end

    test "认证失败分类为 permanent" do
      assert Gong.Retry.classify_error("Invalid API key provided") == :permanent
    end

    test "content_policy 分类为 permanent" do
      assert Gong.Retry.classify_error("stop_reason: content_policy violation") == :permanent
    end

    # pi-mono bugfix 回归
    test "fetch failed 分类为 transient (Pi#fb6d464)" do
      assert Gong.Retry.classify_error("fetch failed") == :transient
    end

    test "connection error 分类为 transient (Pi#c138281)" do
      assert Gong.Retry.classify_error("connection error") == :transient
    end

    test "connection terminated 分类为 transient (Pi#9b84857)" do
      assert Gong.Retry.classify_error("connection terminated unexpectedly") == :transient
    end
  end

  describe "delay_ms/1" do
    test "attempt 0 延迟 1000ms" do
      assert Gong.Retry.delay_ms(0) == 1000
    end

    test "attempt 2 延迟 4000ms（指数退避）" do
      assert Gong.Retry.delay_ms(2) == 4000
    end
  end

  describe "is_retryable_error/1 判定优先级" do
    test "错误类型优先于 HTTP 状态码和标签" do
      decision =
        Gong.Retry.is_retryable_error(%{
          type: "invalid_request",
          status: 503,
          tags: ["retryable"]
        })

      assert decision.retryable == false
      assert decision.error_class == :permanent
      assert decision.source == :error_type
      assert decision.reason == :non_retryable_error_type
      assert decision.matched == "invalid_request"
    end

    test "错误类型命中可重试时忽略不可重试状态码" do
      decision =
        Gong.Retry.is_retryable_error(%{
          type: "timeout",
          status: 400
        })

      assert decision.retryable == true
      assert decision.error_class == :transient
      assert decision.source == :error_type
    end

    test "HTTP 状态码命中 429/5xx 可重试" do
      assert %{retryable: true, source: :http_status, matched: 429} =
               Gong.Retry.is_retryable_error(%{status: 429})

      assert %{retryable: true, source: :http_status, matched: 502} =
               Gong.Retry.is_retryable_error(%{status_code: 502})
    end

    test "仅标签可用时读取标签判定" do
      decision = Gong.Retry.is_retryable_error(%{metadata: %{tags: ["transient"]}})
      assert decision.retryable == true
      assert decision.source == :tag
      assert decision.reason == :retryable_tag
    end

    test "兜底分支遇到未实现 String.Chars 的 map 不抛异常" do
      decision = Gong.Retry.is_retryable_error(%{message: "plain"})
      assert decision.retryable == false
      assert decision.source == :none
      assert decision.reason == :unknown
    end
  end

  describe "should_retry?/2" do
    test "transient attempt=0 返回 true" do
      assert Gong.Retry.should_retry?(:transient, 0) == true
    end

    test "transient attempt=3 返回 false（超过最大重试）" do
      assert Gong.Retry.should_retry?(:transient, 3) == false
    end

    test "permanent 返回 false" do
      assert Gong.Retry.should_retry?(:permanent, 0) == false
    end

    test "统一判定结果可直接用于 should_retry?/2" do
      decision = Gong.Retry.is_retryable_error(%{status: 429})
      assert Gong.Retry.should_retry?(decision, 0) == true
      assert Gong.Retry.should_retry?(decision, 3) == false
    end
  end
end
