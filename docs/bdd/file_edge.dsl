# 文件操作边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的文件编码和路径问题

# ══════════════════════════════════════════════
# Group 1: 文件编码边界（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: FILE-ERR-001] TITLE: NFD/NFC Unicode 路径规范化 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="café.txt" content="hello"
WHEN tool_read path="café.txt"
THEN assert_tool_success content_contains="hello"

[SCENARIO: FILE-ERR-002] TITLE: CRLF 行尾编辑匹配 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="crlf.txt" content="hello\r\nworld\r\n"
WHEN tool_edit path="crlf.txt" old_string="hello" new_string="hi"
THEN assert_tool_success
THEN assert_file_has_crlf path="crlf.txt"

[SCENARIO: FILE-ERR-003] TITLE: UTF-8 BOM 编辑匹配 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_bom_file path="bom.txt" content="hello world"
WHEN tool_edit path="bom.txt" old_string="hello" new_string="hi"
THEN assert_tool_success
THEN assert_file_has_bom path="bom.txt"
