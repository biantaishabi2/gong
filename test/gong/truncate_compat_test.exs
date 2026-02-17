defmodule Gong.TruncateCompatTest do
  use ExUnit.Case, async: true

  describe "legacy compatibility" do
    test "truncate/3 返回旧 Result 结构体" do
      content = "line1\nline2\nline3"

      result = Gong.Truncate.truncate(content, :head, max_lines: 1, max_bytes: 1_000)

      assert %Gong.Truncate.Result{} = result
      assert result.__struct__ == Gong.Truncate.Result
      assert result.truncated == true
      assert result.truncated_by == :lines
      assert result.output_lines == 1
    end

    test "truncate_line/2 返回旧 Result 结构体" do
      content = String.duplicate("a", 20)

      result = Gong.Truncate.truncate_line(content, 5)

      assert %Gong.Truncate.Result{} = result
      assert result.__struct__ == Gong.Truncate.Result
      assert result.truncated == true
      assert result.truncated_by == :chars
      assert result.content =~ "... [truncated]"
    end
  end
end
