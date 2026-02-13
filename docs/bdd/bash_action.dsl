# Bash Action BDD 测试
# 对应 architecture.md J.2 节
# 当前覆盖核心场景，高级进程管理场景待后续补充

# ── 1. 基本执行 ──

[SCENARIO: BDD-BASH-001] TITLE: 简单命令 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo hello"
THEN assert_tool_success content_contains="hello"
THEN assert_exit_code expected=0

[SCENARIO: BDD-BASH-002] TITLE: 命令错误码 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="exit 1"
THEN assert_exit_code expected=1
THEN assert_output_contains text="exited with code 1"

[SCENARIO: BDD-BASH-003] TITLE: 命令前缀环境变量 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="TEST_VAR=hello; echo $TEST_VAR"
THEN assert_tool_success content_contains="hello"

[SCENARIO: BDD-BASH-004] TITLE: 多行输出 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="printf 'line1\nline2\nline3\n'"
THEN assert_tool_success content_contains="line1"
THEN assert_output_contains text="line2"
THEN assert_output_contains text="line3"

# ── 2. 错误处理 ──

[SCENARIO: BDD-BASH-005] TITLE: 超时 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="tail -f /dev/null" timeout=1
THEN assert_output_contains text="timed out after 1 seconds"
THEN assert_result_field field="timed_out" expected="true"

[SCENARIO: BDD-BASH-006] TITLE: 不存在的工作目录 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo test" cwd="/this/directory/does/not/exist"
THEN assert_tool_error error_contains="ENOENT"

[SCENARIO: BDD-BASH-007] TITLE: 空命令 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command=""
THEN assert_tool_error error_contains="cannot be empty"

# ── 3. 输出管理 ──

[SCENARIO: BDD-BASH-008] TITLE: stderr 和 stdout 合并 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo out; echo err >&2"
THEN assert_tool_success content_contains="out"
THEN assert_output_contains text="err"

[SCENARIO: BDD-BASH-009] TITLE: 工作目录设置 TAGS: unit external_io
GIVEN create_temp_dir
GIVEN create_temp_file path="subdir/marker.txt" content="found"
WHEN tool_bash command="cat marker.txt" cwd="subdir"
THEN assert_tool_success content_contains="found"

# ── 4. bash 语法兼容 ──

[SCENARIO: BDD-BASH-010] TITLE: bash 特有语法 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="if [[ -f /etc/hosts ]]; then echo yes; fi"
THEN assert_tool_success content_contains="yes"

[SCENARIO: BDD-BASH-011] TITLE: 管道命令 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo hello | tr 'h' 'H'"
THEN assert_tool_success content_contains="Hello"

# ── 5. 环境与进程 ──

[SCENARIO: BDD-BASH-012] TITLE: 环境变量继承 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo $HOME"
THEN assert_tool_success content_contains="/home"

[SCENARIO: BDD-BASH-013] TITLE: 命令不存在 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="nonexistent_command_xyz_123"
THEN assert_exit_code expected=127

[SCENARIO: BDD-BASH-014] TITLE: 返回值含 timed_out 标记 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="echo quick"
THEN assert_tool_success
THEN assert_result_field field="timed_out" expected="false"

# ── 6. 大输出处理 ──

[SCENARIO: BDD-BASH-015] TITLE: 大输出行截断保留尾部 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="seq 1 3000"
THEN assert_tool_success
THEN assert_output_contains text="3000"
THEN assert_output_contains text="omitted"

[SCENARIO: BDD-BASH-016] TITLE: 超大输出字节截断 TAGS: unit external_io
GIVEN create_temp_dir
WHEN tool_bash command="seq 1 50000"
THEN assert_tool_success
THEN assert_result_field field="truncated" expected="true"
THEN assert_output_contains text="50000"
