defmodule Gong.CompactionTest do
  use ExUnit.Case, async: true

  alias Gong.Compaction

  # ── split_by_token_budget ──

  describe "split_by_token_budget/2" do
    test "短消息全部在预算内，不拆分" do
      msgs = [
        %{role: "user", content: "你好"},
        %{role: "assistant", content: "你好呀"},
        %{role: "user", content: "谢谢"}
      ]

      # 预算足够大，全部保留
      {old, recent} = Compaction.split_by_token_budget(msgs, 10_000)
      assert old == []
      assert length(recent) == 3
    end

    test "长工具输出消息按 token 预算只保留最近几条" do
      # 每条约 130 tokens（100个英文单词）
      long = Enum.map_join(1..100, " ", fn i -> "word#{i}" end)

      msgs =
        for i <- 1..10 do
          role = if rem(i, 2) == 1, do: "user", else: "assistant"
          %{role: role, content: long}
        end

      # 预算 300 tokens → 只够保留约 2 条
      {old, recent} = Compaction.split_by_token_budget(msgs, 300)
      assert length(old) > 0
      assert length(recent) >= 2
      assert length(recent) < 10
    end

    test "系统消息始终保留在 recent 中" do
      msgs = [
        %{role: "system", content: "你是助手"},
        %{role: "user", content: Enum.map_join(1..50, " ", fn i -> "word#{i}" end)},
        %{role: "assistant", content: Enum.map_join(1..50, " ", fn i -> "reply#{i}" end)},
        %{role: "user", content: "最新问题"}
      ]

      # 预算仅够 1 条非系统消息
      {_old, recent} = Compaction.split_by_token_budget(msgs, 20)

      roles = Enum.map(recent, fn m -> m.role end)
      assert "system" in roles
    end

    test "至少保留 1 条非系统消息即使超预算" do
      # 单条巨大消息
      huge = String.duplicate("测试内容", 500)

      msgs = [
        %{role: "user", content: huge}
      ]

      # 预算 10 tokens，但仍保留这 1 条
      {old, recent} = Compaction.split_by_token_budget(msgs, 10)
      assert old == []
      assert length(recent) == 1
    end

    test "tool_call/result 配对不被拆分" do
      msgs = [
        %{role: "user", content: "请读文件"},
        %{role: "assistant", content: "好的", tool_calls: [%{id: "c1", function: %{name: "read"}}]},
        %{role: "tool", content: String.duplicate("内容", 100), tool_call_id: "c1"},
        %{role: "assistant", content: "文件内容如上"},
        %{role: "user", content: "最新问题"}
      ]

      # 预算只够最后 2 条，但 tool pair 保护应把 assistant+tool 拉进 recent
      {_old, recent} = Compaction.split_by_token_budget(msgs, 30)

      recent_roles = Enum.map(recent, fn m -> m[:role] || m["role"] end)

      # recent 中如果有 tool 消息，其前面必须有 assistant 消息（配对保护）
      if "tool" in recent_roles do
        tool_idx = Enum.find_index(recent_roles, &(&1 == "tool"))
        assert tool_idx > 0
        assert Enum.at(recent_roles, tool_idx - 1) == "assistant"
      end
    end
  end

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
