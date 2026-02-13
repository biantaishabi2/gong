defmodule Gong.BDD.InstructionRegistries.Model do
  @moduledoc "ModelRegistry BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN: 模型注册 ──

      register_model: %{
        name: :register_model,
        kind: :given,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          provider: %{type: :string, required?: true, allowed: nil},
          model_id: %{type: :string, required?: true, allowed: nil},
          api_key_env: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      init_model_registry: %{
        name: :init_model_registry,
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

      # ── WHEN: 模型操作 ──

      switch_model: %{
        name: :switch_model,
        kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      validate_model: %{
        name: :validate_model,
        kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: 模型断言 ──

      assert_current_model: %{
        name: :assert_current_model,
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
      assert_model_error: %{
        name: :assert_model_error,
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
      assert_model_count: %{
        name: :assert_model_count,
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
