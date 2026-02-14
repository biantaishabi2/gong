# Bash 边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的 bash 输出边界问题

# ══════════════════════════════════════════════
# Group 1: 输出编码边界（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: BASH-ERR-001] TITLE: 二进制/非 UTF-8 输出不崩溃 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="head -c 100 /bin/ls"
THEN assert_tool_success
THEN assert_result_field field="timed_out" expected="false"

[SCENARIO: BASH-ERR-002] TITLE: 输出截断行数计算精确 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="seq 1 5000"
THEN assert_tool_success
THEN assert_output_contains text="omitted"
THEN assert_output_contains text="5000"

[SCENARIO: BASH-ERR-003] TITLE: 含 ANSI 转义码的输出正确处理 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="printf '\033[31mred\033[0m normal'"
THEN assert_tool_success content_contains="red"
THEN assert_output_contains text="normal"

[SCENARIO: BASH-ERR-004] TITLE: Abort 时清理后台进程 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="sleep 300 & sleep 300 & wait" timeout=2
THEN assert_output_contains text="timed out"
THEN assert_result_field field="timed_out" expected="true"
