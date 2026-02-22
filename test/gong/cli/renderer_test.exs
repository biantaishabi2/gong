defmodule Gong.CLI.RendererTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Gong.CLI.Renderer
  alias Gong.Session.Events

  defp make_event(type, payload \\ %{}) do
    %Events{
      event_id: "00000000-0000-7000-8000-000000000001",
      session_id: "test_session",
      command_id: "cmd_test",
      turn_id: 0,
      seq: 1,
      occurred_at: System.os_time(:millisecond),
      ts: System.os_time(:millisecond),
      type: type,
      payload: payload
    }
  end

  describe "逐行流式渲染" do
    test "message.start 延迟前缀（不立即输出）" do
      output = capture_io(fn -> Renderer.render(make_event("message.start")) end)
      assert output == ""
      Process.delete(:gong_stream)
    end

    test "空 message（start→end 无 delta）静默" do
      output = capture_io(fn ->
        Renderer.render(make_event("message.start"))
        Renderer.render(make_event("message.end"))
      end)
      assert output == ""
    end

    test "delta 无换行输出前缀+原文" do
      Renderer.render(make_event("message.start"))

      output =
        capture_io(fn ->
          Renderer.render(make_event("message.delta", %{content: "Hello"}))
        end)

      # 首个 delta 触发前缀输出
      assert output =~ "◆"
      assert output =~ "Hello"
      Process.delete(:gong_stream)
    end

    test "delta 有换行触发擦除+渲染" do
      Renderer.render(make_event("message.start"))

      output =
        capture_io(fn ->
          Renderer.render(make_event("message.delta", %{content: "## 标题\n"}))
        end)

      # 应包含擦除码和渲染后的标题
      assert output =~ "\r\e[J"
      assert output =~ "标题"
      refute output =~ "##"
      Process.delete(:gong_stream)
    end

    test "message.end 处理最后未完成行" do
      Renderer.render(make_event("message.start"))
      capture_io(fn -> Renderer.render(make_event("message.delta", %{content: "**bold**"})) end)

      output = capture_io(fn -> Renderer.render(make_event("message.end")) end)
      assert output =~ "\r\e[J"
      assert output =~ "bold"
      refute output =~ "**"
    end

    test "message.end 有 delta 后正常换行" do
      Renderer.render(make_event("message.start"))
      capture_io(fn -> Renderer.render(make_event("message.delta", %{content: "line\n"})) end)
      output = capture_io(fn -> Renderer.render(make_event("message.end")) end)
      assert output == "\n"
    end

    test "表格行攒缓冲，结束时一次性渲染对齐" do
      output =
        capture_io(fn ->
          Renderer.render(make_event("message.start"))
          Renderer.render(make_event("message.delta", %{content: "| 名称 | 描述 |\n|---|---|\n| 短 | 很长很长的描述 |\n\n"}))
          Renderer.render(make_event("message.end"))
        end)

      # 表格应包含边框
      assert output =~ "┌"
      assert output =~ "┘"
      assert output =~ "短"
      assert output =~ "很长很长的描述"
    end
  end

  describe "tool 事件" do
    test "tool.start 输出工具名（不换行）" do
      event = make_event("tool.start", %{tool_name: "search", tool_args: %{q: "test"}})
      output = capture_io(fn -> Renderer.render(event) end)
      assert output =~ "⚡"
      assert output =~ "search"
      # 不以换行结尾，等 tool.end 追加
      refute String.ends_with?(output, "\n")
    end

    test "tool.end 成功显示 ✓" do
      event = make_event("tool.end", %{success: true})
      output = capture_io(fn -> Renderer.render(event) end)
      assert output =~ "✓"
      refute output =~ "✗"
    end

    test "tool.end 失败显示 ✗" do
      event = make_event("tool.end", %{success: false})
      output = capture_io(fn -> Renderer.render(event) end)
      assert output =~ "✗"
      refute output =~ "✓"
    end

    test "tool.start + tool.end 同行显示" do
      start_event = make_event("tool.start", %{tool_name: "bash", tool_args: %{command: "ls"}})
      end_event = make_event("tool.end", %{success: true})

      output = capture_io(fn ->
        Renderer.render(start_event)
        Renderer.render(end_event)
      end)

      # 整体只有一个换行（来自 tool.end 的 IO.puts）
      lines = String.split(output, "\n", trim: true)
      assert length(lines) == 1
      assert hd(lines) =~ "bash"
      assert hd(lines) =~ "✓"
    end
  end

  describe "error 事件" do
    test "error.stream 输出红色错误" do
      event = make_event("error.stream", %{message: "连接中断"})
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "✗"
    end

    test "error.runtime payload 为空时从 event.error 提取 message" do
      event = %{make_event("error.runtime", %{}) | error: %{code: :network_error, message: "LLM 调用失败"}}
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "LLM 调用失败"
    end

    test "error.runtime payload 和 error 都无 message 时显示未知错误" do
      event = make_event("error.runtime", %{})
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "未知错误"
    end
  end

  describe "truncate/2" do
    test "短字符串不截断" do
      assert Renderer.truncate("short", 10) == "short"
    end

    test "超长截断加省略号" do
      assert Renderer.truncate("abcdefghij", 5) |> String.ends_with?("...")
    end
  end
end
