defmodule Gong.BDD.InstructionRegistries.Common do
  @moduledoc "通用 BDD 指令：测试基础设施（临时文件、时间冻结等）"

  def specs(:v1) do
    %{
      create_temp_dir: %{
        name: :create_temp_dir,
        kind: :given,
        args: %{},
        outputs: %{workspace: :string},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_temp_file: %{
        name: :create_temp_file,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
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
      create_large_file: %{
        name: :create_large_file,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          lines: %{type: :int, required?: true, allowed: nil},
          line_length: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_binary_file: %{
        name: :create_binary_file,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          bytes: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_png_file: %{
        name: :create_png_file,
        kind: :given,
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
      create_symlink: %{
        name: :create_symlink,
        kind: :given,
        args: %{
          link: %{type: :string, required?: true, allowed: nil},
          target: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      set_file_permission: %{
        name: :set_file_permission,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          mode: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      }
    }
  end

  def specs(:v2), do: %{}
end
