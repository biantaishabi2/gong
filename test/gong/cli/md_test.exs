defmodule Gong.CLI.MdTest do
  use ExUnit.Case, async: true

  alias Gong.CLI.Md

  describe "count_display_lines/2" do
    test "单行短文本" do
      assert Md.count_display_lines("hello", 80) == 1
    end

    test "空字符串" do
      assert Md.count_display_lines("", 80) == 1
    end

    test "多行文本" do
      assert Md.count_display_lines("a\nb\nc", 80) == 3
    end

    test "超宽行自动折行" do
      assert Md.count_display_lines(String.duplicate("a", 100), 50) == 2
    end

    test "含 ANSI 转义码不影响计算" do
      assert Md.count_display_lines("\e[1mhello\e[0m", 80) == 1
    end

    test "CJK 双宽计算" do
      # 5个中文 = 10列宽，终端5列 → 2行
      assert Md.count_display_lines("你好世界啊", 10) == 1
      assert Md.count_display_lines("你好世界啊", 9) == 2
    end
  end

  describe "render_inline/1" do
    test "粗体" do
      result = Md.render_inline("Hello **world**")
      assert result =~ "\e[1m"
      assert result =~ "world"
      refute result =~ "**"
    end

    test "行内代码" do
      result = Md.render_inline("Use `mix test`")
      assert result =~ "\e[36m"
      assert result =~ "mix test"
      refute result =~ "`mix"
    end

    test "标题去掉 #" do
      result = Md.render_inline("## 标题")
      assert result =~ "标题"
      refute result =~ "##"
    end

    test "无序列表渲染 bullet" do
      result = Md.render_inline("- item1\n- item2")
      assert result =~ "•"
      assert result =~ "item1"
    end

    test "有序列表保留数字" do
      result = Md.render_inline("1. first\n2. second")
      assert result =~ "1."
      assert result =~ "first"
    end

    test "围栏代码块内容不被替换" do
      text = "```elixir\n**not bold**\n```"
      result = Md.render_inline(text)
      assert result =~ "**not bold**"
    end

    test "引用" do
      result = Md.render_inline("> 引用内容")
      assert result =~ "│"
      assert result =~ "引用内容"
    end

    test "中文标点紧贴也能替换" do
      result = Md.render_inline("包含 **粗体**、`代码`。")
      refute result =~ "**粗"
      refute result =~ "`代码`"
    end
  end
end
