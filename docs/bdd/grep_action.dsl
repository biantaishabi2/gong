# Grep Action BDD 测试
# 对应 architecture.md J.5 节，共 11 个场景

# ── 1. 基本搜索 ──

[SCENARIO: BDD-GREP-001] TITLE: 单文件搜索 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="line1\nhello world\nline3\n"
WHEN tool_grep pattern="hello" path="test.txt"
THEN assert_tool_success content_contains="hello world"

[SCENARIO: BDD-GREP-002] TITLE: 多文件目录搜索 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="a.txt" content="test match here\n"
GIVEN create_temp_file path="b.txt" content="no match\n"
GIVEN create_temp_file path="c.txt" content="another test line\n"
WHEN tool_grep pattern="test"
THEN assert_tool_success content_contains="a.txt"
THEN assert_output_contains text="c.txt"

[SCENARIO: BDD-GREP-003] TITLE: 无匹配 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="hello world\n"
WHEN tool_grep pattern="nonexistent"
THEN assert_tool_success content_contains="No matches"

# ── 2. 搜索选项 ──

[SCENARIO: BDD-GREP-004] TITLE: 正则表达式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="code.txt" content="hello123\nhello456\nworld\n"
WHEN tool_grep pattern="hello[0-9]+"
THEN assert_tool_success content_contains="hello123"
THEN assert_output_contains text="hello456"
THEN assert_output_not_contains text="world"

[SCENARIO: BDD-GREP-005] TITLE: 字面匹配模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="code.txt" content="foo.bar(baz)\nfooXbarX\n"
WHEN tool_grep pattern="foo.bar(" fixed_strings=true
THEN assert_tool_success content_contains="foo.bar(baz)"

[SCENARIO: BDD-GREP-006] TITLE: 大小写不敏感 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="Hello World\nhello world\n"
WHEN tool_grep pattern="HELLO" ignore_case=true
THEN assert_tool_success content_contains="Hello World"

[SCENARIO: BDD-GREP-007] TITLE: 上下文行数 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="line1\nline2\ntarget\nline4\nline5\n"
WHEN tool_grep pattern="target" context=1
THEN assert_tool_success content_contains="target"
THEN assert_output_not_contains text="line1"

# ── 3. 输出模式与过滤 ──

[SCENARIO: BDD-GREP-008] TITLE: files_with_matches 模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="match.txt" content="found it\n"
GIVEN create_temp_file path="no.txt" content="nothing\n"
WHEN tool_grep pattern="found" output_mode="files_with_matches"
THEN assert_tool_success content_contains="match.txt"
THEN assert_output_not_contains text="no.txt"

[SCENARIO: BDD-GREP-009] TITLE: glob 文件过滤 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="code.ex" content="test content\n"
GIVEN create_temp_file path="code.js" content="test content\n"
WHEN tool_grep pattern="test" glob="*.ex"
THEN assert_tool_success content_contains="code.ex"
THEN assert_output_not_contains text="code.js"

[SCENARIO: BDD-GREP-010] TITLE: 二进制文件自动跳过 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="text.txt" content="search target\n"
GIVEN create_binary_file path="binary.bin" bytes=100
WHEN tool_grep pattern="search"
THEN assert_tool_success content_contains="text.txt"
THEN assert_output_not_contains text="binary.bin"

# ── 4. 参数校验 ──

[SCENARIO: BDD-GREP-011] TITLE: 搜索路径不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_grep pattern="test" path="nonexistent_dir"
THEN assert_tool_error error_contains="ENOENT"

# ── 5. count 模式 ──

[SCENARIO: BDD-GREP-012] TITLE: count 输出模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="a.txt" content="hello\nhello\nworld\n"
GIVEN create_temp_file path="b.txt" content="hello\n"
WHEN tool_grep pattern="hello" output_mode="count"
THEN assert_tool_success content_contains="a.txt"
