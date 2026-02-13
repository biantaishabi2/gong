defmodule Gong.BDD.InstructionRegistries.Resource do
  @moduledoc "Resource 发现 BDD 指令注册"

  def specs(:v1) do
    %{
      create_resource_dir: %{
        name: :create_resource_dir,
        kind: :given,
        args: %{
          scope: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_resource_file: %{
        name: :create_resource_file,
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
      load_resources: %{
        name: :load_resources,
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
      reload_resources: %{
        name: :reload_resources,
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
      assert_resource_content: %{
        name: :assert_resource_content,
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
      },
      assert_resource_count: %{
        name: :assert_resource_count,
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
      }
    }
  end

  def specs(:v2), do: %{}
end
