defmodule Gong.BDD.InstructionRegistries.Tools do
  @moduledoc "工具 Action BDD 指令注册"

  def specs(:v1) do
    %{
      # ── WHEN: 工具调用 ──

      tool_read: %{
        name: :tool_read,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          offset: %{type: :int, required?: false, allowed: nil},
          limit: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      tool_write: %{
        name: :tool_write,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_edit: %{
        name: :tool_edit,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          old_string: %{type: :string, required?: true, allowed: nil},
          new_string: %{type: :string, required?: true, allowed: nil},
          replace_all: %{type: :bool, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_bash: %{
        name: :tool_bash,
        kind: :when,
        args: %{
          command: %{type: :string, required?: true, allowed: nil},
          timeout: %{type: :int, required?: false, allowed: nil},
          cwd: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_grep: %{
        name: :tool_grep,
        kind: :when,
        args: %{
          pattern: %{type: :string, required?: true, allowed: nil},
          path: %{type: :string, required?: false, allowed: nil},
          glob: %{type: :string, required?: false, allowed: nil},
          context: %{type: :int, required?: false, allowed: nil},
          ignore_case: %{type: :bool, required?: false, allowed: nil},
          fixed_strings: %{type: :bool, required?: false, allowed: nil},
          output_mode: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_find: %{
        name: :tool_find,
        kind: :when,
        args: %{
          pattern: %{type: :string, required?: true, allowed: nil},
          path: %{type: :string, required?: false, allowed: nil},
          exclude: %{type: :string, required?: false, allowed: nil},
          limit: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_ls: %{
        name: :tool_ls,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: 结果断言 ──

      assert_file_exists: %{
        name: :assert_file_exists,
        kind: :then,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_file_content: %{
        name: :assert_file_content,
        kind: :then,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_result_field: %{
        name: :assert_result_field,
        kind: :then,
        args: %{
          field: %{type: :string, required?: true, allowed: nil},
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_exit_code: %{
        name: :assert_exit_code,
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
      assert_output_contains: %{
        name: :assert_output_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_output_not_contains: %{
        name: :assert_output_not_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      assert_tool_success: %{
        name: :assert_tool_success,
        kind: :then,
        args: %{
          content_contains: %{type: :string, required?: false, allowed: nil},
          truncated: %{type: :bool, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_tool_error: %{
        name: :assert_tool_error,
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
      assert_tool_truncated: %{
        name: :assert_tool_truncated,
        kind: :then,
        args: %{
          truncated_by: %{type: :string, required?: false, allowed: nil},
          original_lines: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_read_image: %{
        name: :assert_read_image,
        kind: :then,
        args: %{
          mime_type: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_read_text: %{
        name: :assert_read_text,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── WHEN: 截断操作 ──

      truncate_head: %{
        name: :truncate_head,
        kind: :when,
        args: %{
          content_var: %{type: :string, required?: true, allowed: nil},
          max_lines: %{type: :int, required?: false, allowed: nil},
          max_bytes: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      truncate_tail: %{
        name: :truncate_tail,
        kind: :when,
        args: %{
          content_var: %{type: :string, required?: true, allowed: nil},
          max_lines: %{type: :int, required?: false, allowed: nil},
          max_bytes: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      truncate_line: %{
        name: :truncate_line,
        kind: :when,
        args: %{
          content_var: %{type: :string, required?: true, allowed: nil},
          max_chars: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: 截断结果断言 ──

      assert_truncation_result: %{
        name: :assert_truncation_result,
        kind: :then,
        args: %{
          truncated: %{type: :bool, required?: false, allowed: nil},
          truncated_by: %{type: :string, required?: false, allowed: nil},
          output_lines: %{type: :int, required?: false, allowed: nil},
          first_line_exceeds_limit: %{type: :bool, required?: false, allowed: nil},
          last_line_partial: %{type: :bool, required?: false, allowed: nil},
          content_contains: %{type: :string, required?: false, allowed: nil},
          valid_utf8: %{type: :bool, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_truncation_notification: %{
        name: :assert_truncation_notification,
        kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
