defmodule Gong.CompactionTest do
  use ExUnit.Case, async: true

  alias Gong.Compaction

  describe "truncate_tool_outputs/2" do
    test "工具消息被正确头尾截断" do
      # 生成超长工具输出（200行）
      long_content = Enum.map_join(1..200, "\n", fn i -> "output line #{i}: " <> String.duplicate("x", 100) end)

      messages = [
        %{role: "tool", content: long_content, tool_call_id: "call_1"}
      ]

      [result_msg] = Compaction.truncate_tool_outputs(messages, 100_000)

      # 内容已被截断
      assert result_msg.content != long_content
      # 包含省略标注
      assert result_msg.content =~ "省略"
      # 保留了头部内容
      assert result_msg.content =~ "output line 1:"
      # 保留了尾部内容
      assert result_msg.content =~ "output line 200:"
    end

    test "非工具消息不受影响" do
      long_content = String.duplicate("x", 50_000)

      messages = [
        %{role: "user", content: long_content},
        %{role: "assistant", content: long_content}
      ]

      result = Compaction.truncate_tool_outputs(messages, 100_000)

      assert result == messages
    end

    test "截断标注包含省略信息" do
      lines = Enum.map_join(1..300, "\n", fn i -> "line #{i}" end)

      messages = [
        %{role: "tool", content: lines, tool_call_id: "call_1"}
      ]

      [result_msg] = Compaction.truncate_tool_outputs(messages, 100_000)

      assert result_msg.content =~ ~r/省略 \d+ 行/
      assert result_msg.content =~ "字节"
    end

    test "短输出不截断" do
      short_content = "OK: test passed"

      messages = [
        %{role: "tool", content: short_content, tool_call_id: "call_1"}
      ]

      result = Compaction.truncate_tool_outputs(messages, 100_000)

      assert result == messages
    end

    test "字符串键消息也能正确处理" do
      long_content = Enum.map_join(1..200, "\n", fn i -> "line #{i}: " <> String.duplicate("y", 100) end)

      messages = [
        %{"role" => "tool", "content" => long_content, "tool_call_id" => "call_1"}
      ]

      [result_msg] = Compaction.truncate_tool_outputs(messages, 100_000)

      assert result_msg["content"] != long_content
      assert result_msg["content"] =~ "省略"
    end
  end
end
