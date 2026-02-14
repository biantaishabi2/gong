# Find Action BDD 测试
# 对应 architecture.md J.6 节，共 7 个场景

# ── 1. 基本查找 ──

[SCENARIO: BDD-FIND-001] TITLE: 含隐藏文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path=".secret/hidden.txt" content="hidden"
GIVEN create_temp_file path="visible.txt" content="visible"
WHEN tool_find pattern="**/*.txt"
THEN assert_tool_success content_contains="visible.txt"
THEN assert_output_contains text="hidden.txt"

[SCENARIO: BDD-FIND-002] TITLE: 嵌套 glob 模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="a/b/deep.ex" content=""
GIVEN create_temp_file path="top.ex" content=""
WHEN tool_find pattern="**/*.ex"
THEN assert_tool_success content_contains="deep.ex"
THEN assert_output_contains text="top.ex"

[SCENARIO: BDD-FIND-003] TITLE: 空结果 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content=""
WHEN tool_find pattern="*.xyz"
THEN assert_tool_success
THEN assert_output_not_contains text=".txt"

# ── 2. 过滤与限制 ──

[SCENARIO: BDD-FIND-004] TITLE: 排除模式 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="keep.txt" content=""
GIVEN create_temp_file path="ignore.log" content=""
WHEN tool_find pattern="*" exclude="*.log"
THEN assert_tool_success content_contains="keep.txt"
THEN assert_output_not_contains text="ignore.log"

[SCENARIO: BDD-FIND-005] TITLE: 结果数限制 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="a.txt" content=""
GIVEN create_temp_file path="b.txt" content=""
GIVEN create_temp_file path="c.txt" content=""
WHEN tool_find pattern="*.txt" limit=2
THEN assert_tool_success content_contains="Showing 2 of 3"

[SCENARIO: BDD-FIND-006] TITLE: 符号链接 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="real.txt" content="target"
GIVEN create_symlink link="link.txt" target="real.txt"
WHEN tool_find pattern="*.txt"
THEN assert_tool_success content_contains="link.txt"

# ── 3. 参数校验 ──

[SCENARIO: BDD-FIND-007] TITLE: 路径不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_find pattern="*.txt" path="nonexistent"
THEN assert_tool_error error_contains="ENOENT"

# ── 4. .gitignore 过滤 ──

[SCENARIO: BDD-FIND-008] TITLE: 尊重 .gitignore TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path=".gitignore" content="*.log\nbuild/\n"
GIVEN create_temp_file path="keep.txt" content=""
GIVEN create_temp_file path="debug.log" content=""
GIVEN create_temp_file path="build/output.js" content=""
WHEN tool_find pattern="**/*"
THEN assert_tool_success content_contains="keep.txt"
THEN assert_output_not_contains text="debug.log"
THEN assert_output_not_contains text="output.js"

# ── 5. 边界补充 ──

[SCENARIO: BDD-FIND-009] TITLE: 深层嵌套查找 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="a/b/c/d/deep.txt" content="deep"
WHEN tool_find pattern="**/*.txt"
THEN assert_tool_success content_contains="deep.txt"
