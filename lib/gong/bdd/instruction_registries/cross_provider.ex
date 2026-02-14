defmodule Gong.BDD.InstructionRegistries.CrossProvider do
  @moduledoc "Cross-provider & Command BDD 指令注册"

  def specs(:v1) do
    %{
      # ── Cross-provider ──
      cross_provider_messages: %{
        name: :cross_provider_messages, kind: :given,
        args: %{count: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      cross_provider_multipart_message: %{
        name: :cross_provider_multipart_message, kind: :given,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      convert_messages: %{
        name: :convert_messages, kind: :when,
        args: %{
          from: %{type: :string, required?: true, allowed: nil},
          to: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      build_handoff_summary: %{
        name: :build_handoff_summary, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_converted_messages: %{
        name: :assert_converted_messages, kind: :then,
        args: %{count: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_handoff_summary_not_empty: %{
        name: :assert_handoff_summary_not_empty, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_content_is_text: %{
        name: :assert_content_is_text, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── Command 注册 ──
      init_command_registry: %{
        name: :init_command_registry, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      register_command: %{
        name: :register_command, kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          description: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      execute_command: %{
        name: :execute_command, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      execute_command_expect_error: %{
        name: :execute_command_expect_error, kind: :when,
        args: %{name: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_command_result: %{
        name: :assert_command_result, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_command_error: %{
        name: :assert_command_error, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :error
      },
      assert_command_count: %{
        name: :assert_command_count, kind: :then,
        args: %{expected: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 补充覆盖 ──
      assert_command_exists: %{
        name: :assert_command_exists, kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil},
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      cross_provider_tool_calls_message: %{
        name: :cross_provider_tool_calls_message, kind: :given,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_converted_has_tool_calls: %{
        name: :assert_converted_has_tool_calls, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 跨厂商边界补充 ──

      cross_provider_messages_with_thinking: %{
        name: :cross_provider_messages_with_thinking, kind: :given,
        args: %{count: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      cross_provider_messages_with_error: %{
        name: :cross_provider_messages_with_error, kind: :given,
        args: %{count: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_error_messages_filtered: %{
        name: :assert_error_messages_filtered, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_handoff_summary_max_lines: %{
        name: :assert_handoff_summary_max_lines, kind: :then,
        args: %{max: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── Provider 兼容性边界 ──

      cross_provider_messages_with_custom_role: %{
        name: :cross_provider_messages_with_custom_role, kind: :given,
        args: %{
          role: %{type: :string, required?: true, allowed: nil},
          count: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      cross_provider_messages_with_string_keys: %{
        name: :cross_provider_messages_with_string_keys, kind: :given,
        args: %{count: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },

      # ── 字段剥离 + 网关路由 + 事件状态 ──
      cross_provider_messages_with_unsupported_fields: %{
        name: :cross_provider_messages_with_unsupported_fields, kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          field: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_fields_stripped: %{
        name: :assert_fields_stripped, kind: :then,
        args: %{field: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      cross_provider_messages_with_gateway: %{
        name: :cross_provider_messages_with_gateway, kind: :given,
        args: %{
          provider: %{type: :string, required?: true, allowed: nil},
          count: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_required_fields_added: %{
        name: :assert_required_fields_added, kind: :then,
        args: %{field: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      register_state_observer_hook: %{
        name: :register_state_observer_hook, kind: :given,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      emit_event_with_message: %{
        name: :emit_event_with_message, kind: :when,
        args: %{content: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_observer_saw_updated_state: %{
        name: :assert_observer_saw_updated_state, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
