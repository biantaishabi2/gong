# 截断系统 BDD 测试
# 对应 architecture.md J.8 节，共 14 个场景

# ── 1. truncate_head（5 个：对应 J.8 spec 1.5, 1.1, 1.3, 1.2, 1.4）──

[SCENARIO: BDD-TRC-001] TITLE: head 空字符串不截断 TAGS: unit test_runtime
GIVEN set_var name="content" value=""
WHEN truncate_head content_var="content" max_bytes=1000
THEN assert_truncation_result truncated=false

[SCENARIO: BDD-TRC-002] TITLE: head 小文本不截断 TAGS: unit test_runtime
GIVEN set_var name="content" value="hello\nworld"
WHEN truncate_head content_var="content" max_bytes=1000 max_lines=100
THEN assert_truncation_result truncated=false

[SCENARIO: BDD-TRC-003] TITLE: head 超字节限制截断 TAGS: unit test_runtime
GIVEN generate_content name="content" lines=10 line_length=100
WHEN truncate_head content_var="content" max_bytes=200
THEN assert_truncation_result truncated=true truncated_by="bytes"

[SCENARIO: BDD-TRC-004] TITLE: head 超行数限制截断 TAGS: unit test_runtime
GIVEN generate_content name="content" lines=100 line_length=10
WHEN truncate_head content_var="content" max_lines=5 max_bytes=100000
THEN assert_truncation_result truncated=true truncated_by="lines" output_lines=5

[SCENARIO: BDD-TRC-005] TITLE: head 首行超限 TAGS: unit test_runtime
GIVEN generate_content name="content" lines=1 line_length=500
WHEN truncate_head content_var="content" max_bytes=100
THEN assert_truncation_result truncated=true truncated_by="bytes" first_line_exceeds_limit=true

# ── 2. truncate_tail（5 个：对应 J.8 spec 2.1, 2.2, 2.3, 2.4, 2.5）──

[SCENARIO: BDD-TRC-006] TITLE: tail 恰好在限制值不截断 TAGS: unit test_runtime
GIVEN set_var name="content" value="aaa\nbbb\nccc"
WHEN truncate_tail content_var="content" max_lines=3 max_bytes=11
THEN assert_truncation_result truncated=false

[SCENARIO: BDD-TRC-007] TITLE: tail 小文本不截断 TAGS: unit test_runtime
GIVEN set_var name="content" value="hello\nworld"
WHEN truncate_tail content_var="content" max_bytes=1000 max_lines=100
THEN assert_truncation_result truncated=false

[SCENARIO: BDD-TRC-008] TITLE: tail 超字节限制截断 TAGS: unit test_runtime
GIVEN generate_content name="content" lines=10 line_length=100
WHEN truncate_tail content_var="content" max_bytes=200
THEN assert_truncation_result truncated=true truncated_by="bytes"

[SCENARIO: BDD-TRC-009] TITLE: tail 超行数限制截断 TAGS: unit test_runtime
GIVEN generate_content name="content" lines=100 line_length=10
WHEN truncate_tail content_var="content" max_lines=5 max_bytes=100000
THEN assert_truncation_result truncated=true truncated_by="lines" output_lines=5

[SCENARIO: BDD-TRC-010] TITLE: tail 末行 UTF-8 安全截断 TAGS: unit test_runtime
GIVEN set_var name="content" value="你好世界测试\n第二行中文\n第三行数据\n第四行内容\n第五行结束"
WHEN truncate_tail content_var="content" max_bytes=40
THEN assert_truncation_result truncated=true truncated_by="bytes" last_line_partial=true valid_utf8=true

# ── 3. truncate_line（2 个：对应 J.8 spec 3.1, 3.2）──

[SCENARIO: BDD-TRC-011] TITLE: line 短行不截断 TAGS: unit test_runtime
GIVEN set_var name="content" value="short line"
WHEN truncate_line content_var="content" max_chars=500
THEN assert_truncation_result truncated=false

[SCENARIO: BDD-TRC-012] TITLE: line 长行截断含 marker TAGS: unit test_runtime
GIVEN generate_content name="content" lines=1 line_length=1000
WHEN truncate_line content_var="content" max_chars=50
THEN assert_truncation_result truncated=true truncated_by="chars" content_contains="... [truncated]"

# ── 4. 截断通知可操作性（2 个：对应 J.8 spec 4.1, 4.2）──

[SCENARIO: BDD-TRC-013] TITLE: read 工具截断含续读提示 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_large_file path="big.txt" lines=500 line_length=200
WHEN tool_read path="big.txt"
THEN assert_truncation_notification contains="offset="

[SCENARIO: BDD-TRC-014] TITLE: bash 工具截断含原始大小 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="seq 1 20000"
THEN assert_truncation_notification contains="字节"
