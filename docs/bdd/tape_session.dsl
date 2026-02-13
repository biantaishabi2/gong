# Session 树形分支 BDD 测试
# 覆盖 Tape 的分支创建、导航、上下文路径

# ══════════════════════════════════════════════
# Group 1: Session 分支 (6 场景)
# ══════════════════════════════════════════════

[SCENARIO: SESSION-001] TITLE: 从中间分支 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="第一条消息"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="user" content="第二条消息"
GIVEN tape_handoff name="phase-2"
GIVEN tape_append anchor="phase-2" kind="user" content="第三条消息"
WHEN tape_branch_from anchor="phase-1"
THEN assert_tape_branches anchor="phase-1" expected=1

[SCENARIO: SESSION-002] TITLE: 分支导航 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="根消息"
GIVEN tape_handoff name="branch-a"
GIVEN tape_append anchor="branch-a" kind="user" content="分支A消息"
WHEN tape_branch_from anchor="session-start"
WHEN tape_navigate anchor="branch-a"
THEN assert_entry_count expected=2

[SCENARIO: SESSION-003] TITLE: 分支上下文 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="根内容"
GIVEN tape_handoff name="child-1"
GIVEN tape_append anchor="child-1" kind="user" content="子内容"
WHEN tape_build_context anchor="child-1"
THEN assert_tape_context_path count=1 contains="子内容"

[SCENARIO: SESSION-004] TITLE: 深度分支 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="level-0"
WHEN tape_branch_from anchor="session-start"
THEN assert_tape_branches anchor="session-start" expected=1

[SCENARIO: SESSION-005] TITLE: 分支后追加 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="原始消息"
GIVEN tape_handoff name="original-path"
GIVEN tape_append anchor="original-path" kind="user" content="原始路径"
WHEN tape_branch_from anchor="session-start"
GIVEN tape_append anchor="original-path" kind="user" content="原路径新增"
THEN assert_entry_count expected=3

[SCENARIO: SESSION-006] TITLE: 分支列表 TAGS: unit session tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="user" content="根"
WHEN tape_branch_from anchor="session-start"
WHEN tape_branch_from anchor="session-start"
THEN assert_tape_branches anchor="session-start" expected=2
