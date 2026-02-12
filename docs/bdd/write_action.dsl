# Write Action BDD 测试
# 对应 architecture.md J.4 节，共 9 个场景

# ── 1. 基本写入 ──

[SCENARIO: BDD-WRITE-001] TITLE: 创建新文件 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="hello.txt" content="hello world"
THEN assert_tool_success
THEN assert_file_exists path="hello.txt"
THEN assert_file_content path="hello.txt" expected="hello world"

[SCENARIO: BDD-WRITE-002] TITLE: 覆写已有文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="old.txt" content="old content"
WHEN tool_write path="old.txt" content="new content"
THEN assert_tool_success
THEN assert_file_content path="old.txt" expected="new content"

[SCENARIO: BDD-WRITE-003] TITLE: 递归创建父目录 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="nested/deep/dir/test.txt" content="deep write"
THEN assert_tool_success
THEN assert_file_exists path="nested/deep/dir/test.txt"
THEN assert_file_content path="nested/deep/dir/test.txt" expected="deep write"

# ── 2. 内容边界 ──

[SCENARIO: BDD-WRITE-004] TITLE: 空内容 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="empty.txt" content=""
THEN assert_tool_success
THEN assert_file_exists path="empty.txt"

[SCENARIO: BDD-WRITE-005] TITLE: UTF-8 多字节 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="utf8.txt" content="你好世界"
THEN assert_tool_success
THEN assert_file_content path="utf8.txt" expected="你好世界"

# ── 3. 安全与错误 ──

[SCENARIO: BDD-WRITE-006] TITLE: 目标是目录 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="" content="test"
THEN assert_tool_error error_contains="directory"

[SCENARIO: BDD-WRITE-007] TITLE: 权限不足的目录 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="readonly_dir/placeholder.txt" content=""
GIVEN set_file_permission path="readonly_dir" mode="555"
WHEN tool_write path="readonly_dir/new_file.txt" content="test"
THEN assert_tool_error error_contains="denied"

[SCENARIO: BDD-WRITE-008] TITLE: tilde 路径展开 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="tilde_test.txt" content="tilde works"
THEN assert_tool_success

[SCENARIO: BDD-WRITE-009] TITLE: 返回字节数 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_write path="bytes.txt" content="12345"
THEN assert_tool_success
THEN assert_result_field field="bytes_written" expected="5"
