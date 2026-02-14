defmodule Gong.BDD.InstructionRegistries.Template do
  @moduledoc "Prompt 模板 BDD 指令注册"

  def specs(:v1) do
    %{
      init_prompt_templates: %{
        name: :init_prompt_templates, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      register_template: %{
        name: :register_template, kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      get_template: %{
        name: :get_template, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      get_template_expect_error: %{
        name: :get_template_expect_error, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      render_template: %{
        name: :render_template, kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          bindings: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_template_exists: %{
        name: :assert_template_exists, kind: :then,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_template_variables: %{
        name: :assert_template_variables, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_rendered_content: %{
        name: :assert_rendered_content, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_template_error: %{
        name: :assert_template_error, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :error
      }
    }
  end

  def specs(:v2), do: %{}
end
