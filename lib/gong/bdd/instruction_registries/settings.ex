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
          key: %{type: :string, required?: false, allowed: nil},
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

      # ── Settings 补充 ──

      assert_setting_nil: %{
        name: :assert_setting_nil,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      list_settings: %{
        name: :list_settings,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_settings_list: %{
        name: :assert_settings_list,
        kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      cleanup_settings: %{
        name: :cleanup_settings,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      get_setting_safe: %{
        name: :get_setting_safe,
        kind: :when,
        args: %{
          key: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── 配置语义 + 热重载 ──
      set_config_empty_array: %{
        name: :set_config_empty_array, kind: :given,
        args: %{key: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_config_blocks_all: %{
        name: :assert_config_blocks_all, kind: :then,
        args: %{key: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_config_no_filter: %{
        name: :assert_config_no_filter, kind: :then,
        args: %{key: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      reload_settings: %{
        name: :reload_settings, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      }
    }
  end

  def specs(:v2), do: %{}
end
