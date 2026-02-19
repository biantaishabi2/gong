defmodule Gong.ThinkingTest do
  use ExUnit.Case, async: true

  # 从 BDD 管线迁移的 Thinking.parse 单元测试

  describe "parse/1" do
    test "有效字符串 high" do
      assert {:ok, :high} = Gong.Thinking.parse("high")
    end

    test "有效字符串 off" do
      assert {:ok, :off} = Gong.Thinking.parse("off")
    end

    test "无效字符串返回 error" do
      assert {:error, :invalid_level} = Gong.Thinking.parse("超高")
    end
  end

  describe "restore_level/3" do
    test "新字段优先" do
      assert {:medium, :new} = Gong.Thinking.restore_level("medium", "high")
    end

    test "新字段无效时回退旧字段" do
      assert {:high, :legacy} = Gong.Thinking.restore_level("invalid", "high")
    end

    test "新旧字段都无效时回退默认值" do
      assert {:off, :default} = Gong.Thinking.restore_level("invalid", "bad")
    end
  end
end
