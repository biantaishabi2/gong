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
      assert Gong.Retry.classify_error("prompt is too long for the context window") == :context_overflow
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
  end
end
