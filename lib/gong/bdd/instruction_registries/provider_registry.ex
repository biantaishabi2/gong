defmodule Gong.BDD.InstructionRegistries.ProviderReg do
  @moduledoc "Provider 注册表 BDD 指令注册"

  def specs(:v1) do
    %{
      init_provider_registry: %{
        name: :init_provider_registry, kind: :when, args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      register_provider: %{
        name: :register_provider, kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          module: %{type: :string, required?: true, allowed: nil},
          priority: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      register_provider_with_invalid_config: %{
        name: :register_provider_with_invalid_config, kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          module: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      switch_provider: %{
        name: :switch_provider, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      switch_provider_expect_error: %{
        name: :switch_provider_expect_error, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      provider_fallback: %{
        name: :provider_fallback, kind: :when,
        args: %{from: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      provider_fallback_expect_error: %{
        name: :provider_fallback_expect_error, kind: :when,
        args: %{from: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_provider_count: %{
        name: :assert_provider_count, kind: :then,
        args: %{expected: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_current_provider: %{
        name: :assert_current_provider, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_provider_error: %{
        name: :assert_provider_error, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :error
      },
      assert_provider_list_order: %{
        name: :assert_provider_list_order, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
