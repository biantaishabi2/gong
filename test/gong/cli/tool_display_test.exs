defmodule Gong.CLI.ToolDisplayTest do
  use ExUnit.Case, async: true

  alias Gong.CLI.ToolDisplay

  describe "format/2 — 按约定参数名自动提取" do
    test "file_path 类工具显示路径" do
      assert ToolDisplay.format("read_file", %{file_path: "/a/b.ex"}) == "/a/b.ex"
      assert ToolDisplay.format("write_file", %{file_path: "/tmp/out.txt"}) == "/tmp/out.txt"
      assert ToolDisplay.format("edit_file", %{file_path: "/src/main.ex", old_string: "foo"}) == "/src/main.ex"
    end

    test "bash 显示命令" do
      assert ToolDisplay.format("bash", %{command: "ls -la"}) == "ls -la"
      assert ToolDisplay.format("bash", %{command: "mix test", timeout: 120}) == "mix test"
    end

    test "grep 显示 pattern（优先于 path）" do
      assert ToolDisplay.format("grep", %{pattern: "foo", path: "/src"}) == "foo"
    end

    test "path 参数" do
      assert ToolDisplay.format("list_directory", %{path: "/tmp"}) == "/tmp"
    end

    test "file_path 优先于 command 和 path" do
      assert ToolDisplay.format("tool", %{file_path: "/a.ex", command: "ls", path: "/b"}) == "/a.ex"
    end
  end

  describe "format/2 — string key 兼容" do
    test "string key 也能提取" do
      assert ToolDisplay.format("read_file", %{"file_path" => "/a/b.ex"}) == "/a/b.ex"
      assert ToolDisplay.format("bash", %{"command" => "ls -la"}) == "ls -la"
    end
  end

  describe "format/2 — fallback" do
    test "无约定参数名 → JSON" do
      assert ToolDisplay.format("custom", %{foo: "bar"}) == ~s({"foo":"bar"})
    end

    test "空 map → 空字符串" do
      assert ToolDisplay.format("tool", %{}) == ""
    end

    test "字符串参数原样返回" do
      assert ToolDisplay.format("tool", "raw string") == "raw string"
    end

    test "其他类型 → inspect" do
      assert ToolDisplay.format("tool", 42) == "42"
      assert ToolDisplay.format("tool", [:a, :b]) == "[:a, :b]"
    end
  end
end
