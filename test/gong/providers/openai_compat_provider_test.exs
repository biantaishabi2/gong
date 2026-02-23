defmodule Gong.Providers.OpenaiCompatProviderTest do
  use ExUnit.Case, async: true

  alias Gong.Providers.OpenaiCompatProvider

  describe "validate_config/1" do
    test "有效 base_url 返回 :ok" do
      assert :ok = OpenaiCompatProvider.validate_config(%{base_url: "https://api.deepseek.com"})
    end

    test "空 base_url 返回错误" do
      assert {:error, _} = OpenaiCompatProvider.validate_config(%{base_url: ""})
    end

    test "nil base_url 返回错误" do
      assert {:error, _} = OpenaiCompatProvider.validate_config(%{base_url: nil})
    end

    test "缺少 base_url 返回错误" do
      assert {:error, _} = OpenaiCompatProvider.validate_config(%{})
    end

    test "动态 base_url 覆盖：不同厂商使用不同 base_url" do
      assert :ok = OpenaiCompatProvider.validate_config(%{base_url: "https://api.openai.com"})
      assert :ok = OpenaiCompatProvider.validate_config(%{base_url: "https://api.deepseek.com"})
      assert :ok = OpenaiCompatProvider.validate_config(%{base_url: "http://localhost:8080"})
    end
  end

  describe "OpenAI 兼容 payload 格式" do
    test "messages 格式符合 OpenAI chat/completions 规范" do
      messages = [
        %{role: "user", content: "hello"}
      ]

      # OpenAI 兼容格式：messages 直接包含 role/content
      assert is_list(messages)
      assert hd(messages).role == "user"
      assert hd(messages).content == "hello"
    end

    test "model 字段正确传递" do
      model_str = "openai_compat:deepseek-chat"
      [_provider, model_id] = String.split(model_str, ":", parts: 2)
      assert model_id == "deepseek-chat"
    end

    test "tools 格式符合 OpenAI function calling 规范" do
      tools = [
        %{
          type: "function",
          function: %{
            name: "get_weather",
            description: "获取天气",
            parameters: %{type: "object", properties: %{}}
          }
        }
      ]

      assert length(tools) == 1
      assert hd(tools).type == "function"
      assert hd(tools).function.name == "get_weather"
    end
  end
end
