# Read Action BDD 测试
# 对应 architecture.md J.3 节，共 20 个场景

# ── 1. 基本读取 ──

[SCENARIO: BDD-READ-001] TITLE: 正常读取文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="line1\nline2\nline3\n"
WHEN tool_read path="test.txt"
THEN assert_tool_success content_contains="line1" truncated=false

[SCENARIO: BDD-READ-002] TITLE: 文件不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_read path="nonexistent.txt"
THEN assert_tool_error error_contains="ENOENT"

[SCENARIO: BDD-READ-003] TITLE: 空文件 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="empty.txt" content=""
WHEN tool_read path="empty.txt"
THEN assert_tool_success truncated=false

# ── 2. 分页 ──

[SCENARIO: BDD-READ-004] TITLE: offset 参数 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="paged.txt" lines=100 line_length=20
WHEN tool_read path="paged.txt" offset=51
THEN assert_tool_success content_contains="line 51"

[SCENARIO: BDD-READ-005] TITLE: limit 参数 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="paged.txt" lines=100 line_length=20
WHEN tool_read path="paged.txt" limit=10
THEN assert_tool_success content_contains="more lines" truncated=true

[SCENARIO: BDD-READ-006] TITLE: offset + limit 组合 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="paged.txt" lines=100 line_length=20
WHEN tool_read path="paged.txt" offset=41 limit=20
THEN assert_tool_success content_contains="line 41"
THEN assert_output_not_contains text="line 61"

[SCENARIO: BDD-READ-007] TITLE: offset=1 边界 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="three.txt" content="aaa\nbbb\nccc\n"
WHEN tool_read path="three.txt" offset=1
THEN assert_tool_success content_contains="aaa"

[SCENARIO: BDD-READ-008] TITLE: offset 越界 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="short.txt" content="a\nb\nc\n"
WHEN tool_read path="short.txt" offset=100
THEN assert_tool_error error_contains="beyond end of file"

# ── 3. 截断 ──

[SCENARIO: BDD-READ-009] TITLE: 行数截断 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="big.txt" lines=2500 line_length=10
WHEN tool_read path="big.txt"
THEN assert_tool_truncated truncated_by="lines" original_lines=2500

[SCENARIO: BDD-READ-010] TITLE: 字节截断 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="wide.txt" lines=500 line_length=200
WHEN tool_read path="wide.txt"
THEN assert_tool_truncated truncated_by="bytes"

[SCENARIO: BDD-READ-011] TITLE: 首行超大 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="oneline.txt" lines=1 line_length=60000
WHEN tool_read path="oneline.txt"
THEN assert_tool_success content_contains="chars truncated"

# ── 4. 图片处理 ──

[SCENARIO: BDD-READ-012] TITLE: PNG MIME 类型检测 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_png_file path="image.txt"
WHEN tool_read path="image.txt"
THEN assert_read_image mime_type="image/png"

[SCENARIO: BDD-READ-013] TITLE: 非图片但图片扩展名 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="fake.png" content="this is plain text"
WHEN tool_read path="fake.png"
THEN assert_read_text

# ── 5. 文件系统边界 ──

[SCENARIO: BDD-READ-014] TITLE: 截断详情元数据 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="meta.txt" lines=2500 line_length=10
WHEN tool_read path="meta.txt"
THEN assert_tool_truncated truncated_by="lines" original_lines=2500

[SCENARIO: BDD-READ-015] TITLE: offset=最后一行 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="hundred.txt" lines=100 line_length=10
WHEN tool_read path="hundred.txt" offset=100
THEN assert_tool_success content_contains="line 100"

[SCENARIO: BDD-READ-016] TITLE: 符号链接 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="real.txt" content="target content here"
GIVEN create_symlink link="link.txt" target="real.txt"
WHEN tool_read path="link.txt"
THEN assert_tool_success content_contains="target content"

[SCENARIO: BDD-READ-017] TITLE: 权限不足 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="locked.txt" content="secret"
GIVEN set_file_permission path="locked.txt" mode="000"
WHEN tool_read path="locked.txt"
THEN assert_tool_error error_contains="EACCES"

# ── 6. Pi 历史 bug 回归 + 参数校验 ──

[SCENARIO: BDD-READ-018] TITLE: 特殊字符文件名 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="截图 2026-02-11.txt" content="chinese filename"
WHEN tool_read path="截图 2026-02-11.txt"
THEN assert_tool_success content_contains="chinese filename"

[SCENARIO: BDD-READ-019] TITLE: tilde 路径展开 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="tilde_test.txt" content="tilde works"
WHEN tool_read path="tilde_test.txt"
THEN assert_tool_success content_contains="tilde works"

[SCENARIO: BDD-READ-020] TITLE: 目录路径拒绝 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="subdir/placeholder.txt" content=""
WHEN tool_read path="subdir"
THEN assert_tool_error error_contains="Is a directory"

# ── 7. BOM 和格式检测补充 ──

[SCENARIO: BDD-READ-021] TITLE: BOM 文件读取跳过 BOM TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_bom_file path="bom.txt" content="BOM content here"
WHEN tool_read path="bom.txt"
THEN assert_tool_success content_contains="BOM content"

[SCENARIO: BDD-READ-022] TITLE: 二进制文件拒绝读取 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_binary_file path="data.bin" bytes=100
WHEN tool_read path="data.bin"
THEN assert_tool_error error_contains="Binary file"

[SCENARIO: BDD-READ-023] TITLE: JPEG 图片检测 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_png_file path="photo.jpg"
WHEN tool_read path="photo.jpg"
THEN assert_read_image mime_type="image/png"
