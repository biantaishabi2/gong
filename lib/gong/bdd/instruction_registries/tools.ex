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

      # ── THEN: 结果断言 ──

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
      }
    }
  end

  def specs(:v2), do: %{}
end
