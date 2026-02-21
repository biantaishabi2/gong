defmodule Gong.CLI.MdTest do
  use ExUnit.Case, async: true

  alias Gong.CLI.Md

  describe "render_line/2" do
    test "标题去掉 # 加黄色粗体" do
      {result, in_code} = Md.render_line("## 标题", false)
      assert result =~ "标题"
      assert result =~ "\e[1m"
      assert result =~ "\e[33m"
      refute result =~ "##"
      assert in_code == false
    end

    test "粗体" do
      {result, _} = Md.render_line("Hello **world**", false)
      assert result =~ "\e[1m"
      assert result =~ "world"
      refute result =~ "**"
    end

    test "行内代码" do
      {result, _} = Md.render_line("Use `mix test`", false)
      assert result =~ "\e[36m"
      refute result =~ "`"
    end

    test "无序列表" do
      {result, _} = Md.render_line("- item1", false)
      assert result =~ "•"
      assert result =~ "item1"
      refute result =~ "- "
    end

    test "有序列表" do
      {result, _} = Md.render_line("1. first", false)
      assert result =~ "1."
      assert result =~ "first"
    end

    test "引用" do
      {result, _} = Md.render_line("> 引用内容", false)
      assert result =~ "│"
      assert result =~ "引用内容"
    end

    test "围栏代码块开启" do
      {result, in_code} = Md.render_line("```elixir", false)
      assert result == ""
      assert in_code == true
    end

    test "代码块内容青色" do
      {result, in_code} = Md.render_line("def hello, do: :world", true)
      assert result =~ "\e[36m"
      assert result =~ "def hello"
      assert in_code == true
    end

    test "围栏代码块关闭" do
      {result, in_code} = Md.render_line("```", true)
      assert result == ""
      assert in_code == false
    end

    test "代码块内不做行内替换" do
      {result, _} = Md.render_line("**not bold** `not code`", true)
      assert result =~ "**not bold**"
      assert result =~ "`not code`"
    end

    test "中文标点紧贴也能替换" do
      {result, _} = Md.render_line("包含 **粗体**、`代码`。", false)
      refute result =~ "**粗"
      refute result =~ "`代码`"
    end

    test "空行" do
      {result, _} = Md.render_line("", false)
      assert result == ""
    end
  end

  describe "render_inline/1" do
    test "多行完整渲染" do
      text = "## 标题\n\n**粗体**\n\n- item1\n- item2"
      result = Md.render_inline(text)
      refute result =~ "##"
      refute result =~ "**"
      assert result =~ "•"
    end
  end

  describe "display_width/1" do
    test "ASCII" do
      assert Md.display_width("hello") == 5
    end

    test "CJK 双宽" do
      assert Md.display_width("你好") == 4
    end

    test "混合" do
      assert Md.display_width("hi你好") == 6
    end

    test "忽略 ANSI" do
      assert Md.display_width("\e[1mhello\e[0m") == 5
    end
  end

  describe "count_display_lines/2" do
    test "单行" do
      assert Md.count_display_lines("hello", 80) == 1
    end

    test "多行" do
      assert Md.count_display_lines("a\nb\nc", 80) == 3
    end

    test "CJK 双宽" do
      assert Md.count_display_lines("你好世界啊", 10) == 1
      assert Md.count_display_lines("你好世界啊", 9) == 2
    end

    test "含 ANSI 不影响" do
      assert Md.count_display_lines("\e[1mhello\e[0m", 80) == 1
    end
  end
end
