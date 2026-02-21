defmodule Gong.CostTrackerTest do
  use ExUnit.Case, async: true

  alias Gong.CostTracker

  describe "calculate_cost/3" do
    test "已知模型返回正确成本" do
      # deepseek-chat: input $0.14/M, output $0.28/M
      cost = CostTracker.calculate_cost("deepseek:deepseek-chat", 1_000_000, 1_000_000)
      assert_in_delta cost, 0.14 + 0.28, 0.0001
    end

    test "零 token 返回零成本" do
      cost = CostTracker.calculate_cost("deepseek:deepseek-chat", 0, 0)
      assert cost == 0.0
    end

    test "未知模型使用默认单价" do
      # 默认: input $1.00/M, output $2.00/M
      cost = CostTracker.calculate_cost("unknown:model", 1000, 500)
      expected = 1000 * 1.0e-6 + 500 * 2.0e-6
      assert_in_delta cost, expected, 1.0e-10
    end

    test "OpenAI 模型价格正确" do
      # gpt-4o: input $2.50/M, output $10.00/M
      cost = CostTracker.calculate_cost("openai:gpt-4o", 100, 200)
      expected = 100 * 2.5e-6 + 200 * 10.0e-6
      assert_in_delta cost, expected, 1.0e-10
    end

    test "Anthropic 模型价格正确" do
      # claude-3-5-sonnet: input $3.00/M, output $15.00/M
      cost = CostTracker.calculate_cost("anthropic:claude-3-5-sonnet", 500, 300)
      expected = 500 * 3.0e-6 + 300 * 15.0e-6
      assert_in_delta cost, expected, 1.0e-10
    end
  end
end
