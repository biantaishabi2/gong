defmodule Gong.HookTest do
  use ExUnit.Case, async: true

  # pi-mono bugfix 回归: Hook.build_message role 和 content 归一化
  # Pi#ecef601: role 应为 "hookMessage" 而非 "user"
  # Pi#574f1cb: 字符串 content 归一化为数组

  describe "build_message/1" do
    test "字符串参数返回 role=hookMessage" do
      msg = Gong.Hook.build_message("hook test")
      assert msg.role == "hookMessage"
    end

    test "字符串 content 归一化为数组" do
      msg = Gong.Hook.build_message("test string")
      assert is_list(msg.content)
      assert [%{type: "text", text: "test string"}] = msg.content
    end

    test "列表参数直接作为 content" do
      parts = [%{type: "text", text: "hello"}]
      msg = Gong.Hook.build_message(parts)
      assert msg.role == "hookMessage"
      assert msg.content == parts
    end
  end
end
