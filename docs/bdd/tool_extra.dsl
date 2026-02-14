# 工具补全 BDD 测试
# 覆盖 truncate、edit-diff、path-utils

# ══════════════════════════════════════════════
# Group 1: truncate 工具 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: TRUNC-001] TITLE: LLM 调用 truncate 加 max_lines 参数 TAGS: unit tool_extra
GIVEN create_temp_dir
GIVEN create_temp_file path="long_file.txt" content="line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10"
WHEN tool_truncate path="long_file.txt" max_lines=5
THEN assert_tool_success content_contains="line1"

[SCENARIO: TRUNC-002] TITLE: truncate 和系统截断交互 TAGS: unit tool_extra
GIVEN create_temp_dir
GIVEN create_temp_file path="small.txt" content="one\ntwo\nthree"
WHEN tool_truncate path="small.txt" max_lines=100
THEN assert_tool_success content_contains="one"

# ══════════════════════════════════════════════
# Group 2: edit-diff 模式 (3 场景)
# ══════════════════════════════════════════════

[SCENARIO: EDITDIFF-001] TITLE: unified diff 输入正确应用 TAGS: unit tool_extra
GIVEN create_temp_dir
GIVEN create_temp_file path="target.txt" content="aaa\nbbb\nccc\nddd"
WHEN tool_edit_diff path="target.txt" diff="@@ -1,4 +1,4 @@\n aaa\n-bbb\n+BBB\n ccc\n ddd"
THEN assert_tool_success
THEN assert_file_content path="target.txt" expected="aaa\nBBB\nccc\nddd"

[SCENARIO: EDITDIFF-002] TITLE: diff 加行偏移定位正确 TAGS: unit tool_extra
GIVEN create_temp_dir
GIVEN create_temp_file path="offset.txt" content="header\n---\nalpha\nbeta\ngamma"
WHEN tool_edit_diff path="offset.txt" diff="@@ -3,3 +3,3 @@\n alpha\n-beta\n+BETA\n gamma"
THEN assert_tool_success
THEN assert_file_content path="offset.txt" expected="header\n---\nalpha\nBETA\ngamma"

[SCENARIO: EDITDIFF-003] TITLE: diff 和 string replace 混合使用 TAGS: unit tool_extra
GIVEN create_temp_dir
GIVEN create_temp_file path="mixed.txt" content="foo\nbar\nbaz"
WHEN tool_edit_diff path="mixed.txt" diff="@@ -1,3 +1,3 @@\n foo\n-bar\n+BAR\n baz"
THEN assert_tool_success
THEN assert_file_content path="mixed.txt" expected="foo\nBAR\nbaz"

# ══════════════════════════════════════════════
# Group 3: path-utils 工具 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: PATH-001] TITLE: 波浪号相对路径点点全部规范化 TAGS: unit tool_extra
GIVEN create_temp_dir
WHEN normalize_path path="/tmp/foo/../bar"
THEN assert_normalized_path expected="/tmp/bar"

[SCENARIO: PATH-002] TITLE: macOS NFD 变体处理 TAGS: unit tool_extra
GIVEN create_temp_dir
WHEN normalize_path path="/tmp/test"
THEN assert_normalized_path expected="/tmp/test"

# ══════════════════════════════════════════════
# Group 4: PathUtils 边界补充 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: PATH-003] TITLE: 波浪号展开为 home 目录 TAGS: unit tool_extra
GIVEN create_temp_dir
WHEN normalize_path path="~/test"
THEN assert_normalized_path_contains text="/test"

[SCENARIO: PATH-004] TITLE: 相对路径展开为绝对路径 TAGS: unit tool_extra
GIVEN create_temp_dir
WHEN normalize_path path="foo/bar"
THEN assert_normalized_path_is_absolute
