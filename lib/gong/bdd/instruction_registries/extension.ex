defmodule Gong.BDD.InstructionRegistries.Extension do
  @moduledoc "Extension 加载 BDD 指令注册"

  def specs(:v1) do
    %{
      create_extension_dir: %{
        name: :create_extension_dir,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_extension_file: %{
        name: :create_extension_file,
        kind: :given,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      discover_extensions: %{
        name: :discover_extensions,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      load_extension: %{
        name: :load_extension,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      load_all_extensions: %{
        name: :load_all_extensions,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_extension_loaded: %{
        name: :assert_extension_loaded,
        kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_extension_tools: %{
        name: :assert_extension_tools,
        kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_extension_error: %{
        name: :assert_extension_error,
        kind: :then,
        args: %{
          error_contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :error
      },
      assert_extension_count: %{
        name: :assert_extension_count,
        kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── 补充覆盖 ──
      assert_extension_commands: %{
        name: :assert_extension_commands,
        kind: :then,
        args: %{expected: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      cleanup_extension: %{
        name: :cleanup_extension,
        kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_extension_cleanup_called: %{
        name: :assert_extension_cleanup_called,
        kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── 扩展禁用/冲突/导入 ──
      set_no_extensions_flag: %{
        name: :set_no_extensions_flag, kind: :given,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      discover_extensions_with_flag: %{
        name: :discover_extensions_with_flag, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_no_extensions_loaded: %{
        name: :assert_no_extensions_loaded, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      create_conflicting_extensions: %{
        name: :create_conflicting_extensions, kind: :given,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_extension_conflict_error: %{
        name: :assert_extension_conflict_error, kind: :then,
        args: %{error_contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :error
      },
      create_extension_with_import: %{
        name: :create_extension_with_import, kind: :given,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          import_path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      load_extension_with_imports: %{
        name: :load_extension_with_imports, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_import_resolved: %{
        name: :assert_import_resolved, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── pi-mono bugfix 回归 ──

      build_hook_message: %{
        name: :build_hook_message, kind: :when,
        args: %{content: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_hook_message_role: %{
        name: :assert_hook_message_role, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      build_hook_message_string: %{
        name: :build_hook_message_string, kind: :when,
        args: %{content: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_hook_message_content_is_array: %{
        name: :assert_hook_message_content_is_array, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_conflicting_extension_removed: %{
        name: :assert_conflicting_extension_removed, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── pi-mono bugfix 回归 #21-#26 ──

      normalize_git_url: %{
        name: :normalize_git_url, kind: :when,
        args: %{url: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_normalized_url: %{
        name: :assert_normalized_url, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      format_load_error: %{
        name: :format_load_error, kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          reason: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_error_info_contains: %{
        name: :assert_error_info_contains, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      check_local_path: %{
        name: :check_local_path, kind: :when,
        args: %{path: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_is_local: %{
        name: :assert_is_local, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      merge_extension_paths: %{
        name: :merge_extension_paths, kind: :when,
        args: %{
          cli: %{type: :string, required?: true, allowed: nil},
          settings: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_merged_paths: %{
        name: :assert_merged_paths, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      normalize_at_prefix: %{
        name: :normalize_at_prefix, kind: :when,
        args: %{path: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      # assert_normalized_path 已在 tool_extra 注册表中定义，此处复用
      build_extension_context: %{
        name: :build_extension_context, kind: :when,
        args: %{model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      update_extension_context_model: %{
        name: :update_extension_context_model, kind: :when,
        args: %{model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_extension_context_model: %{
        name: :assert_extension_context_model, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
