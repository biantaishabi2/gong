defmodule Gong.Extension.SourceTest do
  use ExUnit.Case, async: true

  alias Gong.Extension.Source

  # pi-mono bugfix 回归: Extension 路径处理工具函数
  # Pi#21-#25 对应的纯函数单元测试

  describe "normalize_git_url/1" do
    test "移除 .git 后缀" do
      assert Source.normalize_git_url("https://github.com/anthropic/pi-mono.git") ==
               "https://github.com/anthropic/pi-mono"
    end

    test "无 .git 后缀不变" do
      assert Source.normalize_git_url("https://github.com/anthropic/pi-mono") ==
               "https://github.com/anthropic/pi-mono"
    end
  end

  describe "local_path?/1" do
    test ".pi/ 路径识别为本地" do
      assert Source.local_path?(".pi/extensions/my_ext") == true
    end

    test "http URL 不是本地路径" do
      assert Source.local_path?("https://github.com/ext.git") == false
    end
  end

  describe "merge_paths/2" do
    test "合并去重保持顺序" do
      assert Source.merge_paths(["./a", "./b"], ["./b", "./c"]) == ["./a", "./b", "./c"]
    end

    test "空列表合并" do
      assert Source.merge_paths([], ["./a"]) == ["./a"]
    end
  end

  describe "normalize_at_prefix/1" do
    test "移除 @ 前缀" do
      assert Source.normalize_at_prefix("@anthropic/claude-ext") == "anthropic/claude-ext"
    end

    test "无 @ 前缀不变" do
      assert Source.normalize_at_prefix("local/ext") == "local/ext"
    end
  end
end
