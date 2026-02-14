# Hook/扩展边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的 hook 链式执行和隔离

# ══════════════════════════════════════════════
# Group 1: Hook 链式执行（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: EXT-ERR-001] TITLE: 多扩展 hook 链式执行 TAGS: integration hook
GIVEN create_temp_dir
GIVEN create_temp_file path="chain.txt" content="链式测试"
GIVEN configure_agent model="mock"
GIVEN register_hook module="AllowAll"
GIVEN register_hook module="AllowAll"
GIVEN attach_telemetry_handler event="gong.tool.start"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/chain.txt"
GIVEN mock_llm_response response_type="text" content="链式完成"
WHEN agent_chat prompt="读取文件"
THEN assert_agent_reply contains="链式完成"
THEN assert_hook_fired event="gong.tool.start"

[SCENARIO: EXT-ERR-002] TITLE: 符号链接扩展能被发现 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="real_ext.ex" content="defmodule SymlinkExt do\n  use Gong.Extension\n  def name, do: \"symlink_ext\"\nend"
GIVEN create_symlink link="extensions/link_ext.ex" target="extensions/real_ext.ex"
WHEN load_all_extensions
THEN assert_extension_loaded name="SymlinkExt"

[SCENARIO: EXT-ERR-003] TITLE: 扩展冲突时有明确错误提示 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_conflicting_extensions
WHEN load_all_extensions
THEN assert_extension_conflict_error error_contains="conflict"

# ══════════════════════════════════════════════
# Group 2: Hook 深拷贝与容错（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: EXT-ERR-004] TITLE: Hook 接收的 messages 是深拷贝 TAGS: integration hook
GIVEN create_temp_dir
GIVEN create_temp_file path="test.txt" content="深拷贝测试"
GIVEN configure_agent model="mock"
GIVEN register_hook module="MessageMutatorHook"
GIVEN register_hook module="AllowAll"
GIVEN mock_llm_response response_type="tool_call" tool="read_file" tool_args="file_path={{workspace}}/test.txt"
GIVEN mock_llm_response response_type="text" content="深拷贝正常"
WHEN agent_chat prompt="测试深拷贝"
THEN assert_agent_reply contains="深拷贝正常"

[SCENARIO: EXT-ERR-005] TITLE: 扩展禁用标志在所有代码路径生效 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="test_ext.ex" content="defmodule TestFlagExt do\n  use Gong.Extension\n  def name, do: \"test_flag_ext\"\nend"
GIVEN set_no_extensions_flag
WHEN discover_extensions_with_flag
THEN assert_no_extensions_loaded

[SCENARIO: EXT-ERR-006] TITLE: Custom tool 子路径 import 正确解析 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_with_import name="import_ext.ex" import_path="./helpers/utils.ex"
WHEN load_extension_with_imports
THEN assert_import_resolved
