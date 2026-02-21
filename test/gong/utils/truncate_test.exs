defmodule Gong.Utils.TruncateTest do
  use ExUnit.Case, async: true

  alias Gong.Utils.Truncate
  alias Gong.Utils.Truncate.Result

  describe "truncate_head_tail/2" do
    test "1000行输出头尾保留" do
      # 生成 1000 行文本
      lines = for i <- 1..1000, do: "line_#{String.pad_leading(Integer.to_string(i), 3, "0")}"
      content = Enum.join(lines, "\n")

      result = Truncate.truncate_head_tail(content)

      assert %Result{truncated: true, truncated_by: :lines} = result
      output_lines = String.split(result.content, "\n")

      # 头 50 行
      head = Enum.take(output_lines, 50)
      assert hd(head) == "line_001"
      assert List.last(head) == "line_050"

      # 尾 50 行
      tail = Enum.take(output_lines, -50)
      assert hd(tail) == "line_951"
      assert List.last(tail) == "line_1000"

      # 中间标注
      marker_line = Enum.at(output_lines, 50)
      assert marker_line =~ "省略 900 行"
      assert marker_line =~ "字节"

      assert result.total_lines == 1000
    end

    test "50行不截断" do
      lines = for i <- 1..50, do: "short line #{i}"
      content = Enum.join(lines, "\n")

      result = Truncate.truncate_head_tail(content)

      assert %Result{truncated: false} = result
      assert result.content == content
      assert result.total_lines == 50
    end

    test "单行超长按字节截断" do
      # 50000 字节的单行
      content = String.duplicate("A", 50_000)

      result = Truncate.truncate_head_tail(content)

      assert %Result{truncated: true, truncated_by: :bytes} = result
      assert result.total_lines == 1
      assert result.total_bytes == 50_000
      # 输出应包含标注
      assert result.content =~ "省略"
      assert result.content =~ "字节"
      # 输出字节应小于原始
      assert byte_size(result.content) < 50_000
    end

    test "恰好等于阈值（100行 = head 50 + tail 50）不截断" do
      lines = for i <- 1..100, do: "line #{i}"
      content = Enum.join(lines, "\n")

      result = Truncate.truncate_head_tail(content)

      assert %Result{truncated: false} = result
      assert result.content == content
      assert result.total_lines == 100
    end

    test "自定义参数" do
      lines = for i <- 1..20, do: "line_#{i}"
      content = Enum.join(lines, "\n")

      result = Truncate.truncate_head_tail(content, head_lines: 3, tail_lines: 3)

      assert %Result{truncated: true, truncated_by: :lines} = result
      output_lines = String.split(result.content, "\n")

      assert hd(output_lines) == "line_1"
      assert Enum.at(output_lines, 2) == "line_3"
      assert List.last(output_lines) == "line_20"
      assert Enum.at(output_lines, 3) =~ "省略 14 行"
    end

    test "空内容不截断" do
      result = Truncate.truncate_head_tail("")

      assert %Result{truncated: false} = result
      assert result.content == ""
    end

    test "UTF-8 边界安全" do
      # 包含多字节 UTF-8 字符的长内容
      line = String.duplicate("你好世界", 5_000)
      # 每个中文字符 3 字节，4字符 = 12字节，5000次 = 60000字节 > 30000
      result = Truncate.truncate_head_tail(line)

      assert %Result{truncated: true, truncated_by: :bytes} = result
      # 确保结果是有效 UTF-8
      assert String.valid?(result.content)
    end

    test "行数+字节双重截断" do
      # 200 行，每行 500 字节 → 总约 100KB，行数超限且字节也超限
      lines = for i <- 1..200, do: "line_#{i}_" <> String.duplicate("X", 490)
      content = Enum.join(lines, "\n")

      result = Truncate.truncate_head_tail(content)

      assert %Result{truncated: true} = result
      # 先行截断再字节截断 → truncated_by 为 [:lines, :bytes]
      assert result.truncated_by == [:lines, :bytes]
      assert byte_size(result.content) <= 30_100  # 允许 marker 额外字节
    end
  end
end
