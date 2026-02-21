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
    test "message.start 输出前缀" do
      output = capture_io(fn -> Renderer.render(make_event("message.start")) end)
      assert output =~ "◆"
      Process.delete(:gong_stream)
    end

    test "delta 无换行直接输出原文" do
      capture_io(fn -> Renderer.render(make_event("message.start")) end)

      output =
        capture_io(fn ->
          Renderer.render(make_event("message.delta", %{content: "Hello"}))
        end)

      assert output == "Hello"
      Process.delete(:gong_stream)
    end

    test "delta 有换行触发擦除+渲染" do
      capture_io(fn -> Renderer.render(make_event("message.start")) end)

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
      capture_io(fn -> Renderer.render(make_event("message.start")) end)
      capture_io(fn -> Renderer.render(make_event("message.delta", %{content: "**bold**"})) end)

      output = capture_io(fn -> Renderer.render(make_event("message.end")) end)
      assert output =~ "\r\e[J"
      assert output =~ "bold"
      refute output =~ "**"
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
    end
  end

  describe "error 事件" do
    test "error.stream 输出红色错误" do
      event = make_event("error.stream", %{message: "连接中断"})
      output = capture_io(:stderr, fn -> Renderer.render(event) end)
      assert output =~ "✗"
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
