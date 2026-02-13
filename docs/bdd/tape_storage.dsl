# Tape 存储 BDD 测试
# 阶段五：基于 Pi SessionManager bug 修复历史的回归测试，共 20 个场景

# ══════════════════════════════════════════════
# Group 1: 初始化（2 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-001] TITLE: 工作区初始化 TAGS: unit tape
GIVEN create_temp_dir
WHEN when_tape_init
THEN assert_dir_exists path="anchors/001_session-start"
THEN assert_db_exists
THEN assert_anchor_count expected=1

[SCENARIO: BDD-TAPE-002] TITLE: 重复初始化幂等 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_init
THEN assert_anchor_count expected=1
THEN assert_db_exists

# ══════════════════════════════════════════════
# Group 2: 追加（4 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-003] TITLE: 追加消息条目 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_append kind="message" content="hello world"
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="hello world"
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-004] TITLE: 追加工具调用条目 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_append kind="tool_call" content="read_file /tmp/test"
THEN assert_jsonl_contains path="anchors/001_session-start/tool_calls.jsonl" text="read_file"
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-005] TITLE: 双写一致性 — DB 可从文件重建 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="msg1"
GIVEN tape_append kind="message" content="msg2"
GIVEN tape_append kind="message" content="msg3"
GIVEN delete_file path="index.db"
WHEN when_tape_rebuild_index
THEN assert_entry_count expected=3

[SCENARIO: BDD-TAPE-006] TITLE: 追加到不存在的 anchor TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_append anchor="nonexistent" kind="message" content="fail"
THEN assert_tape_error error_contains="anchor not found"

# ══════════════════════════════════════════════
# Group 3: Handoff / 锚点管理（3 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-007] TITLE: 创建新锚点 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_handoff name="phase-1"
THEN assert_dir_exists path="anchors/002_phase-1"
THEN assert_anchor_count expected=2

[SCENARIO: BDD-TAPE-008] TITLE: 锚点顺序编号 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_handoff name="phase-1"
WHEN when_tape_handoff name="phase-2"
THEN assert_dir_exists path="anchors/002_phase-1"
THEN assert_dir_exists path="anchors/003_phase-2"
THEN assert_anchor_count expected=3

[SCENARIO: BDD-TAPE-009] TITLE: handoff 后追加写入新锚点 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_handoff name="phase-1"
WHEN when_tape_append kind="message" content="phase1 msg"
THEN assert_jsonl_contains path="anchors/002_phase-1/messages.jsonl" text="phase1 msg"
THEN assert_jsonl_not_contains path="anchors/001_session-start/messages.jsonl" text="phase1 msg"

# ══════════════════════════════════════════════
# Group 4: 查询（3 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-010] TITLE: 按锚点范围查询 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append anchor="session-start" kind="message" content="start msg"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="message" content="phase1 msg"
WHEN when_tape_between_anchors start="session-start" end="session-start"
THEN assert_query_results count=1 contains="start msg"

[SCENARIO: BDD-TAPE-011] TITLE: 全文搜索命中 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="发生了错误信息"
WHEN when_tape_search query="错误"
THEN assert_search_results count=1 contains="错误信息"

[SCENARIO: BDD-TAPE-012] TITLE: 全文搜索无结果 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="normal message"
WHEN when_tape_search query="不存在的关键词"
THEN assert_search_results count=0

# ══════════════════════════════════════════════
# Group 5: Fork / Merge（4 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-013] TITLE: fork 创建隔离工作区 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
WHEN when_tape_fork
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-014] TITLE: fork 写入不污染父工作区 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_append kind="message" content="fork msg"
GIVEN tape_restore_parent
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-015] TITLE: merge 合并 fork 数据 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_append kind="message" content="fork new msg"
WHEN when_tape_merge
THEN assert_entry_count expected=2

[SCENARIO: BDD-TAPE-016] TITLE: merge 无新数据不影响父工作区 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_restore_parent
WHEN when_tape_merge
THEN assert_entry_count expected=1

# ══════════════════════════════════════════════
# Group 6: 文件损坏恢复（3 个）— Pi bug 回归
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-017] TITLE: malformed JSON 行跳过 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="good msg"
GIVEN corrupt_jsonl path="anchors/001_session-start/messages.jsonl" line_content="this is not json{{"
WHEN when_tape_append kind="message" content="another good msg"
THEN assert_entry_count expected=2

[SCENARIO: BDD-TAPE-018] TITLE: 空 JSONL 文件恢复 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="will be cleared"
GIVEN tape_append kind="tool_call" content="tool data"
GIVEN clear_file path="anchors/001_session-start/messages.jsonl"
WHEN when_tape_rebuild_index
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-019] TITLE: DB 丢失后从文件重建 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="rebuild msg 1"
GIVEN tape_append kind="message" content="rebuild msg 2"
GIVEN tape_append kind="tool_call" content="rebuild tool"
GIVEN delete_file path="index.db"
WHEN when_tape_rebuild_index
THEN assert_entry_count expected=3
THEN assert_anchor_count expected=1

# ══════════════════════════════════════════════
# Group 7: 边界条件（1 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-020] TITLE: UTF-8 多字节内容存取 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
WHEN when_tape_append kind="message" content="中文消息 🎉 emoji测试"
THEN assert_entry_count expected=1
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="中文消息"
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="🎉"

# ══════════════════════════════════════════════
# Group 8: 覆盖缺口补充（6 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-021] TITLE: between_anchors 跨 anchor 范围查询 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append anchor="session-start" kind="message" content="start msg"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="message" content="phase1 msg"
WHEN when_tape_between_anchors start="session-start" end="phase-1"
THEN assert_query_results count=2 contains="start msg"

[SCENARIO: BDD-TAPE-022] TITLE: search 跨 anchor 搜索 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append anchor="session-start" kind="message" content="搜索目标alpha"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="message" content="搜索目标beta"
WHEN when_tape_search query="搜索目标"
THEN assert_search_results count=2

[SCENARIO: BDD-TAPE-023] TITLE: handoff 重复名称返回错误 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_handoff name="phase-1"
WHEN when_tape_handoff name="phase-1"
THEN assert_tape_error error_contains="anchor already exists"

[SCENARIO: BDD-TAPE-024] TITLE: merge 失败回滚 — 父 DB 损坏 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_append kind="message" content="fork new msg"
GIVEN tape_restore_parent
GIVEN tape_close_db
WHEN when_tape_merge
THEN assert_tape_error error_contains="merge failed"

[SCENARIO: BDD-TAPE-025] TITLE: rebuild_index 多 anchor 多 kind 重建 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append anchor="session-start" kind="message" content="msg1"
GIVEN tape_append anchor="session-start" kind="tool_call" content="tool1"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="message" content="msg2"
GIVEN delete_file path="index.db"
WHEN when_tape_rebuild_index
THEN assert_entry_count expected=3
THEN assert_anchor_count expected=2

[SCENARIO: BDD-TAPE-026] TITLE: 同 anchor 混合 kind 文件分离 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="hello"
GIVEN tape_append kind="tool_call" content="tool data"
WHEN when_tape_append kind="message" content="world"
THEN assert_entry_count expected=3
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="hello"
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="world"
THEN assert_jsonl_contains path="anchors/001_session-start/tool_calls.jsonl" text="tool data"

[SCENARIO: BDD-TAPE-027] TITLE: merge 合并 fork 中新建的 anchor TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_handoff name="fork-phase"
GIVEN tape_append anchor="fork-phase" kind="message" content="fork phase msg"
GIVEN tape_restore_parent
WHEN when_tape_merge
THEN assert_entry_count expected=2
THEN assert_anchor_count expected=2
THEN assert_dir_exists path="anchors/002_fork-phase"

# ══════════════════════════════════════════════
# Group 9: Pi bug 回归补充（3 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-028] TITLE: 重复初始化保留已有数据 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="existing msg"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="tool_call" content="existing tool"
WHEN when_tape_init
THEN assert_entry_count expected=2
THEN assert_anchor_count expected=2
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="existing msg"
THEN assert_jsonl_contains path="anchors/002_phase-1/tool_calls.jsonl" text="existing tool"

[SCENARIO: BDD-TAPE-029] TITLE: 自定义 kind 追加写入独立文件 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="normal msg"
WHEN when_tape_append kind="event" content="custom event data"
THEN assert_entry_count expected=2
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="normal msg"
THEN assert_jsonl_contains path="anchors/001_session-start/events.jsonl" text="custom event data"

[SCENARIO: BDD-TAPE-030] TITLE: fork 保留多 anchor 完整结构 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append anchor="session-start" kind="message" content="start msg"
GIVEN tape_handoff name="phase-1"
GIVEN tape_append anchor="phase-1" kind="message" content="phase1 msg"
GIVEN tape_handoff name="phase-2"
GIVEN tape_append anchor="phase-2" kind="tool_call" content="phase2 tool"
WHEN when_tape_fork
THEN assert_entry_count expected=3
THEN assert_anchor_count expected=3
THEN assert_jsonl_contains path="anchors/001_session-start/messages.jsonl" text="start msg"
THEN assert_jsonl_contains path="anchors/002_phase-1/messages.jsonl" text="phase1 msg"
THEN assert_jsonl_contains path="anchors/003_phase-2/tool_calls.jsonl" text="phase2 tool"

# ══════════════════════════════════════════════
# Group 10: Bub bug 回归（2 个）
# ══════════════════════════════════════════════

[SCENARIO: BDD-TAPE-031] TITLE: 合法 JSON 但字段类型错误的行被跳过 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="good msg"
GIVEN corrupt_jsonl path="anchors/001_session-start/messages.jsonl" line_content="{\"id\": null, \"kind\": 123, \"content\": null, \"timestamp\": \"bad\"}"
GIVEN delete_file path="index.db"
WHEN when_tape_rebuild_index
THEN assert_entry_count expected=1

[SCENARIO: BDD-TAPE-032] TITLE: merge 后 fork 临时目录被清理 TAGS: unit tape
GIVEN create_temp_dir
GIVEN tape_init
GIVEN tape_append kind="message" content="parent msg"
GIVEN tape_fork
GIVEN tape_append kind="message" content="fork msg"
GIVEN tape_restore_parent
WHEN when_tape_merge
THEN assert_entry_count expected=2
THEN assert_fork_cleaned
