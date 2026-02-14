defmodule Gong.BDD.InstructionRegistries.Thinking do
  @moduledoc "Thinking 预算 BDD 指令注册"

  def specs(:v1) do
    %{
      validate_thinking_level: %{
        name: :validate_thinking_level, kind: :when,
        args: %{level: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      get_thinking_budget: %{
        name: :get_thinking_budget, kind: :when,
        args: %{level: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      thinking_to_provider: %{
        name: :thinking_to_provider, kind: :when,
        args: %{
          level: %{type: :string, required?: true, allowed: nil},
          provider: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_thinking_valid: %{
        name: :assert_thinking_valid, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_thinking_invalid: %{
        name: :assert_thinking_invalid, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_thinking_budget: %{
        name: :assert_thinking_budget, kind: :then,
        args: %{expected: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_thinking_params: %{
        name: :assert_thinking_params, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_thinking_params_empty: %{
        name: :assert_thinking_params_empty, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
