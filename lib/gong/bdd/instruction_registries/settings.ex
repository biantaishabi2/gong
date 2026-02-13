defmodule Gong.BDD.InstructionRegistries.Settings do
  @moduledoc "Settings 管理 BDD 指令注册"

  def specs(:v1) do
    %{
      init_settings: %{
        name: :init_settings,
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
      create_settings_file: %{
        name: :create_settings_file,
        kind: :given,
        args: %{
          scope: %{type: :string, required?: true, allowed: nil},
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
      get_setting: %{
        name: :get_setting,
        kind: :when,
        args: %{
          key: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      set_setting: %{
        name: :set_setting,
        kind: :when,
        args: %{
          key: %{type: :string, required?: true, allowed: nil},
          value: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_setting_value: %{
        name: :assert_setting_value,
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
