# 分支摘要 BDD 测试
# 覆盖切换分支时的自动摘要生成

# ══════════════════════════════════════════════
# Group 1: 分支摘要 (2 场景)
# ══════════════════════════════════════════════

[SCENARIO: BRANCHSUM-001] TITLE: 切换分支时自动生成摘要 TAGS: unit branch_summary
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="Hello"
GIVEN tape_append kind="assistant" content="Hi there"
GIVEN tape_handoff name="branch_a"
GIVEN tape_append kind="user" content="How are you?"
GIVEN tape_append kind="assistant" content="I am fine"
WHEN generate_branch_summary anchor="branch_a"
THEN assert_branch_summary contains="How are you"

[SCENARIO: BRANCHSUM-002] TITLE: 摘要包含分支关键操作 TAGS: unit branch_summary
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="Write code"
GIVEN tape_append kind="assistant" content="Here is the code"
GIVEN tape_handoff name="code_branch"
GIVEN tape_append kind="user" content="Run tests"
GIVEN tape_append kind="tool_use" content="bash: ls -la"
WHEN generate_branch_summary anchor="code_branch"
THEN assert_branch_summary contains="Run tests"

# ══════════════════════════════════════════════
# pi-mono bugfix 回归覆盖
# ══════════════════════════════════════════════

[SCENARIO: BRANCHSUM-003] TITLE: 多层分支选最深公共祖先 (Pi#92947a3) TAGS: unit branch_summary regression
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="root"
GIVEN tape_handoff name="level-1"
GIVEN tape_append kind="user" content="branch L1"
GIVEN tape_handoff name="level-2"
GIVEN tape_append kind="user" content="branch L2"
WHEN find_deepest_common_ancestor anchor_a="level-1" anchor_b="level-2"
THEN assert_common_ancestor expected="level-1"
