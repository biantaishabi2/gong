# Extension 加载/发现 BDD 测试
# 覆盖 Extension 的发现、加载、生命周期

# ══════════════════════════════════════════════
# Group 1: Extension 系统 (6 场景)
# ══════════════════════════════════════════════

[SCENARIO: EXTEND-001] TITLE: 发现 .ex 文件 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="test_ext.ex" content="defmodule TestDiscoverExt do\n  use Gong.Extension\n  def name, do: \"test_discover\"\nend"
WHEN load_all_extensions
THEN assert_extension_count expected=1
THEN assert_extension_loaded name="TestDiscoverExt"

[SCENARIO: EXTEND-002] TITLE: Hook 回调注册 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="hook_ext.ex" content="defmodule HookExt do\n  use Gong.Extension\n  def name, do: \"hook_ext\"\n  def hooks, do: [Gong.TestHooks.AllowAll]\nend"
WHEN load_extension path="hook_ext.ex"
THEN assert_extension_loaded name="HookExt"

[SCENARIO: EXTEND-003] TITLE: 自定义工具注册 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="tool_ext.ex" content="defmodule ToolExt do\n  use Gong.Extension\n  def name, do: \"tool_ext\"\n  def tools, do: [Gong.Tools.Read]\nend"
WHEN load_extension path="tool_ext.ex"
THEN assert_extension_loaded name="ToolExt"
THEN assert_extension_tools expected=1

[SCENARIO: EXTEND-004] TITLE: 加载失败隔离 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="bad_ext.ex" content="defmodule BadExt do\n  this is invalid syntax\nend"
GIVEN create_extension_file name="good_ext.ex" content="defmodule GoodExt do\n  use Gong.Extension\n  def name, do: \"good_ext\"\nend"
WHEN load_all_extensions
THEN assert_extension_count expected=1
THEN assert_extension_loaded name="GoodExt"

[SCENARIO: EXTEND-005] TITLE: 多 Extension 加载 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="ext_a.ex" content="defmodule ExtA do\n  use Gong.Extension\n  def name, do: \"ext_a\"\n  def tools, do: [Gong.Tools.Read]\nend"
GIVEN create_extension_file name="ext_b.ex" content="defmodule ExtB do\n  use Gong.Extension\n  def name, do: \"ext_b\"\n  def tools, do: [Gong.Tools.Write]\nend"
WHEN load_all_extensions
THEN assert_extension_count expected=2

[SCENARIO: EXTEND-006] TITLE: Extension 生命周期 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="lifecycle_ext.ex" content="defmodule LifecycleExt do\n  use Gong.Extension\n  def name, do: \"lifecycle\"\n  def init(_opts), do: {:ok, %{initialized: true}}\n  def cleanup(_state), do: :ok\nend"
WHEN load_extension path="lifecycle_ext.ex"
THEN assert_extension_loaded name="LifecycleExt"

# ══════════════════════════════════════════════
# Group 2: Extension 深层补充（3 场景）
# ══════════════════════════════════════════════

[SCENARIO: EXTEND-007] TITLE: 空 extensions 目录不崩溃 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
WHEN load_all_extensions
THEN assert_extension_count expected=0

[SCENARIO: EXTEND-008] TITLE: Extension 重复加载幂等 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="idempotent.ex" content="defmodule IdempotentExt do\n  use Gong.Extension\n  def name, do: \"idempotent\"\nend"
WHEN load_all_extensions
WHEN load_all_extensions
THEN assert_extension_loaded name="IdempotentExt"

[SCENARIO: EXTEND-009] TITLE: Extension 无 name 回调处理 TAGS: unit extension
GIVEN create_temp_dir
GIVEN create_extension_dir
GIVEN create_extension_file name="noname.ex" content="defmodule NoNameExt do\n  use Gong.Extension\nend"
WHEN load_all_extensions
THEN assert_extension_count expected=1
