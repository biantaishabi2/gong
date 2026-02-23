defmodule Gong.Providers.AnthropicCompatProviderTest do
  use ExUnit.Case, async: true

  alias Gong.Providers.AnthropicCompatProvider

  describe "validate_config/1" do
    test "有效 base_url 返回 :ok" do
      assert :ok = AnthropicCompatProvider.validate_config(%{base_url: "https://api.anthropic.com"})
    end

    test "空 base_url 返回错误" do
      assert {:error, _} = AnthropicCompatProvider.validate_config(%{base_url: ""})
    end

    test "nil base_url 返回错误" do
      assert {:error, _} = AnthropicCompatProvider.validate_config(%{base_url: nil})
    end

    test "缺少 base_url 返回错误" do
      assert {:error, _} = AnthropicCompatProvider.validate_config(%{})
    end
  end

  describe "build_payload/3" do
    test "system 消息提取为顶层参数" do
      messages = [
        %{role: "system", content: "you are helpful"},
        %{role: "user", content: "hello"}
      ]

      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet")

      assert payload.system == "you are helpful"
      assert payload.model == "claude-3-sonnet"
      assert length(payload.messages) == 1
      assert hd(payload.messages).role == "user"
    end

    test "无 system 消息时不包含 system 字段" do
      messages = [
        %{role: "user", content: "hello"}
      ]

      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet")

      refute Map.has_key?(payload, :system)
      assert payload.model == "claude-3-sonnet"
      assert length(payload.messages) == 1
    end

    test "多个 system 消息合并为一个" do
      messages = [
        %{role: "system", content: "rule 1"},
        %{role: "system", content: "rule 2"},
        %{role: "user", content: "hello"}
      ]

      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet")

      assert payload.system == "rule 1\nrule 2"
      assert length(payload.messages) == 1
    end

    test "支持字符串 key 的消息格式" do
      messages = [
        %{"role" => "system", "content" => "you are helpful"},
        %{"role" => "user", "content" => "hello"}
      ]

      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet")

      assert payload.system == "you are helpful"
      assert length(payload.messages) == 1
    end

    test "默认 max_tokens 为 4096" do
      messages = [%{role: "user", content: "hello"}]
      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet")
      assert payload.max_tokens == 4096
    end

    test "自定义 max_tokens" do
      messages = [%{role: "user", content: "hello"}]
      payload = AnthropicCompatProvider.build_payload(messages, "claude-3-sonnet", max_tokens: 1024)
      assert payload.max_tokens == 1024
    end
  end

  describe "default_headers/0" do
    test "包含 anthropic-version header" do
      headers = AnthropicCompatProvider.default_headers()

      assert Map.has_key?(headers, "anthropic-version")
      assert headers["anthropic-version"] == "2023-06-01"
    end

    test "包含 content-type header" do
      headers = AnthropicCompatProvider.default_headers()
      assert headers["content-type"] == "application/json"
    end
  end
end
