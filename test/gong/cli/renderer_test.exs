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

  describe "message 流式 + 重渲染" do
    test "message.start 输出蓝色前缀并初始化 buffer" do
      output = capture_io(fn -> Renderer.render(make_event("message.start")) end)
      assert output =~ "◆"
      assert Process.get(:gong_stream_buffer) == ""
      Process.delete(:gong_stream_buffer)
    end

    test "message.delta 逐字输出并累积 buffer" do
      capture_io(fn -> Renderer.render(make_event("message.start")) end)

      output =
        capture_io(fn ->
          Renderer.render(make_event("message.delta", %{content: "Hello"}))
        end)

      assert output == "Hello"
      assert Process.get(:gong_stream_buffer) == "Hello"
      Process.delete(:gong_stream_buffer)
    end

    test "message.end 擦除并重渲染 Markdown" do
      capture_io(fn -> Renderer.render(make_event("message.start")) end)
      capture_io(fn -> Renderer.render(make_event("message.delta", %{content: "## Title\n\n**bold**"})) end)

      output = capture_io(fn -> Renderer.render(make_event("message.end")) end)
      # 应包含擦除转义码和 ANSI 格式
      assert output =~ "\e["
      # 标题应被渲染（去掉 ##）
      assert output =~ "Title"
      refute output =~ "##"
    end

    test "message.end 空 buffer 只输出换行" do
      capture_io(fn -> Renderer.render(make_event("message.start")) end)
      output = capture_io(fn -> Renderer.render(make_event("message.end")) end)
      assert output == "\n"
    end
  end

  describe "tool 事件" do
    test "tool.start 输出黄色工具名" do
      event = make_event("tool.start", %{tool_name: "search", tool_args: %{q: "test"}})
      output = capture_io(fn -> Renderer.render(event) end)
      assert output =~ "⚡"
      assert output =~ "search"
    end

    test "tool.end 输出青色结果" do
      event = make_event("tool.end", %{result: "found 3 items"})
      output = capture_io(fn -> Renderer.render(event) end)
      assert output =~ "✓"
      assert output =~ "found 3 items"
    end
  end

  describe "error 事件" do
    test "error.stream 输出红色错误" do
      event = make_event("error.stream", %{message: "连接中断"})
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "✗"
      assert output =~ "连接中断"
    end

    test "error.runtime 嵌套 error map" do
      event = make_event("error.runtime", %{error: %{message: "超时"}})
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "超时"
    end
  end

  describe "truncate/2" do
    test "短字符串不截断" do
      assert Renderer.truncate("short", 10) == "short"
    end

    test "超长字符串截断加省略号" do
      result = Renderer.truncate("abcdefghij", 5)
      assert String.starts_with?(result, "abcde")
      assert String.ends_with?(result, "...")
    end
  end
end
