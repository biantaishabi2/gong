# Edit Action BDD 测试
# 对应 architecture.md J.1 节
# 当前覆盖核心场景，高级场景（CRLF/BOM、并发、路径遍历）待后续补充

# ── 1. 基础替换 ──

[SCENARIO: BDD-EDIT-001] TITLE: 精确匹配替换 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="Hello, world!"
WHEN tool_edit path="test.txt" old_string="world" new_string="testing"
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="Hello, testing!"

[SCENARIO: BDD-EDIT-002] TITLE: 文本不存在 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="Hello, world!"
WHEN tool_edit path="test.txt" old_string="nonexistent" new_string="x"
THEN assert_tool_error error_contains="Could not find"

[SCENARIO: BDD-EDIT-003] TITLE: 多次出现拒绝 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="foo bar foo baz foo"
WHEN tool_edit path="test.txt" old_string="foo" new_string="qux"
THEN assert_tool_error error_contains="3 occurrences"

[SCENARIO: BDD-EDIT-004] TITLE: replace_all 模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="foo bar foo baz foo"
WHEN tool_edit path="test.txt" old_string="foo" new_string="qux" replace_all=true
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="qux bar qux baz qux"

# ── 2. 模糊匹配 ──

[SCENARIO: BDD-EDIT-005] TITLE: 尾部空格容错 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="line one   \nline two\n"
WHEN tool_edit path="test.txt" old_string="line one\nline two" new_string="replaced"
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="replaced\n"

[SCENARIO: BDD-EDIT-006] TITLE: 精确匹配优先 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="hello world"
WHEN tool_edit path="test.txt" old_string="hello world" new_string="goodbye"
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="goodbye"

[SCENARIO: BDD-EDIT-007] TITLE: 模糊也找不到 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="hello world"
WHEN tool_edit path="test.txt" old_string="completely different" new_string="x"
THEN assert_tool_error error_contains="Could not find"

# ── 3. 安全与边界 ──

[SCENARIO: BDD-EDIT-008] TITLE: old_string 为空拒绝 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="hello"
WHEN tool_edit path="test.txt" old_string="" new_string="content"
THEN assert_tool_error error_contains="cannot be empty"

[SCENARIO: BDD-EDIT-009] TITLE: no-op 检测 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="hello"
WHEN tool_edit path="test.txt" old_string="hello" new_string="hello"
THEN assert_tool_error error_contains="identical"

[SCENARIO: BDD-EDIT-010] TITLE: 目标是目录 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="subdir/placeholder.txt" content=""
WHEN tool_edit path="subdir" old_string="x" new_string="y"
THEN assert_tool_error error_contains="directory"

[SCENARIO: BDD-EDIT-011] TITLE: 文件不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_edit path="nonexistent.txt" old_string="x" new_string="y"
THEN assert_tool_error error_contains="not found"

[SCENARIO: BDD-EDIT-012] TITLE: 权限不足 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="locked.txt" content="secret"
GIVEN set_file_permission path="locked.txt" mode="444"
WHEN tool_edit path="locked.txt" old_string="secret" new_string="open"
THEN assert_tool_error error_contains="Read-only"

# ── 4. 多行替换 ──

[SCENARIO: BDD-EDIT-013] TITLE: 多行文本替换 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="line1\nline2\nline3\nline4\n"
WHEN tool_edit path="test.txt" old_string="line2\nline3" new_string="replaced2\nreplaced3"
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="line1\nreplaced2\nreplaced3\nline4\n"

[SCENARIO: BDD-EDIT-014] TITLE: 返回替换次数 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="aaa bbb ccc"
WHEN tool_edit path="test.txt" old_string="bbb" new_string="xxx"
THEN assert_tool_success
THEN assert_result_field field="replacements" expected="1"

[SCENARIO: BDD-EDIT-015] TITLE: replace_all 返回替换次数 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="aa bb aa cc aa"
WHEN tool_edit path="test.txt" old_string="aa" new_string="zz" replace_all=true
THEN assert_tool_success
THEN assert_result_field field="replacements" expected="3"

# ── 5. UTF-8 内容 ──

[SCENARIO: BDD-EDIT-016] TITLE: 中文内容替换 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="你好世界"
WHEN tool_edit path="test.txt" old_string="世界" new_string="Elixir"
THEN assert_tool_success
THEN assert_file_content path="test.txt" expected="你好Elixir"
