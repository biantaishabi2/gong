defmodule Gong.BDD.InstructionRegistries.ToolExtra do
  @moduledoc "工具补全 BDD 指令注册（truncate、edit-diff、path-utils）"

  def specs(:v1) do
    %{
      tool_truncate: %{
        name: :tool_truncate,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          max_lines: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tool_edit_diff: %{
        name: :tool_edit_diff,
        kind: :when,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          diff: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      normalize_path: %{
        name: :normalize_path,
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
      assert_normalized_path: %{
        name: :assert_normalized_path,
        kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
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
