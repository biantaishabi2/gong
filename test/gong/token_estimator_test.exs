defmodule Gong.Compaction.TokenEstimatorTest do
  use ExUnit.Case, async: true

  # pi-mono bugfix 回归: Token 估算精度
  # 中文按字符计数，英文按空格分词

  describe "estimate/1" do
    test "中文纯文本精度" do
      # "你好世界测试" 6 个中文字符，估算应考虑多字节
      estimate = Gong.Compaction.TokenEstimator.estimate("你好世界测试")
      assert estimate == 12
    end

    test "英文纯文本精度" do
      # "hello world test" 3 个英文单词
      estimate = Gong.Compaction.TokenEstimator.estimate("hello world test")
      assert estimate == 4
    end
  end
end
