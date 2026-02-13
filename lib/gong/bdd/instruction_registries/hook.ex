defmodule Gong.BDD.InstructionRegistries.Hook do
  @moduledoc "Hook 系统 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN: Hook 配置 ──

      attach_telemetry_handler: %{
        name: :attach_telemetry_handler,
        kind: :given,
        args: %{
          event: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      configure_hooks: %{
        name: :configure_hooks,
        kind: :given,
        args: %{
          hooks: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Hook 断言 ──

      assert_telemetry_received: %{
        name: :assert_telemetry_received,
        kind: :then,
        args: %{
          event: %{type: :string, required?: true, allowed: nil},
          metadata_contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_hook_error_logged: %{
        name: :assert_hook_error_logged,
        kind: :then,
        args: %{
          hook: %{type: :string, required?: true, allowed: nil},
          has_stacktrace: %{type: :bool, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_result_content_contains: %{
        name: :assert_result_content_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_result_content_not_contains: %{
        name: :assert_result_content_not_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_conversation_contains: %{
        name: :assert_conversation_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
