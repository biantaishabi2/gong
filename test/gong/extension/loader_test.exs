defmodule Gong.Extension.LoaderTest do
  use ExUnit.Case, async: true

  # pi-mono bugfix 回归: 扩展加载失败错误日志格式
  # Pi#22

  describe "format_load_error/2" do
    test "包含文件名" do
      result = Gong.Extension.Loader.format_load_error("bad_ext.ex", "syntax error")
      assert String.contains?(result, "bad_ext.ex")
    end

    test "包含错误原因" do
      result = Gong.Extension.Loader.format_load_error("/path/to/ext.ex", :enoent)
      assert String.contains?(result, "enoent")
    end
  end
end
