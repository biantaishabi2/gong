# Ls Action BDD 测试
# 对应 architecture.md J.7 节，共 7 个场景

# ── 1. 基本列表 ──

[SCENARIO: BDD-LS-001] TITLE: 列出目录内容含类型后缀 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="file.txt" content="hello"
GIVEN create_temp_file path="subdir/nested.txt" content="nested"
WHEN tool_ls path=""
THEN assert_tool_success content_contains="file.txt"
THEN assert_output_contains text="subdir/"

[SCENARIO: BDD-LS-002] TITLE: 空目录 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_ls path=""
THEN assert_tool_success
THEN assert_output_not_contains text=".txt"

[SCENARIO: BDD-LS-003] TITLE: 排序验证 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="zebra.txt" content=""
GIVEN create_temp_file path="apple.txt" content=""
GIVEN create_temp_file path="banana.txt" content=""
WHEN tool_ls path=""
THEN assert_tool_success content_contains="apple.txt"
THEN assert_output_contains text="banana.txt"
THEN assert_output_contains text="zebra.txt"

# ── 2. 错误与边界 ──

[SCENARIO: BDD-LS-004] TITLE: 路径是文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="afile.txt" content="not a dir"
WHEN tool_ls path="afile.txt"
THEN assert_tool_error error_contains="Not a directory"

[SCENARIO: BDD-LS-005] TITLE: 路径不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_ls path="nonexistent_dir"
THEN assert_tool_error error_contains="ENOENT"

[SCENARIO: BDD-LS-006] TITLE: 隐藏文件可见 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path=".hidden" content="secret"
GIVEN create_temp_file path="visible.txt" content="public"
WHEN tool_ls path=""
THEN assert_tool_success content_contains=".hidden"
THEN assert_output_contains text="visible.txt"

# ── 3. 参数校验 ──

[SCENARIO: BDD-LS-007] TITLE: 大小格式化 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="small.txt" content="abc"
WHEN tool_ls path=""
THEN assert_tool_success content_contains="3B"
