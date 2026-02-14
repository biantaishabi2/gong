defmodule Gong.BDD.InstructionRegistries.Abort do
  @moduledoc "Abort 信号 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN: Abort 配置 ──

      setup_abort_scenario: %{
        name: :setup_abort_scenario,
        kind: :given,
        args: %{
          after_tool: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN: Abort 操作 ──

      send_abort_signal: %{
        name: :send_abort_signal,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Abort 断言 ──

      assert_aborted: %{
        name: :assert_aborted,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_abort_reset: %{
        name: :assert_abort_reset,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      # ── WHEN: Abort unit ──

      abort_signal: %{
        name: :abort_signal,
        kind: :when,
        args: %{
          reason: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      abort_check_catch: %{
        name: :abort_check_catch,
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
      abort_reset: %{
        name: :abort_reset,
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
      abort_safe_execute: %{
        name: :abort_safe_execute,
        kind: :when,
        args: %{
          will_abort: %{type: :string, required?: false, allowed: nil},
          reason: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Abort unit 断言 ──

      assert_abort_flag: %{
        name: :assert_abort_flag,
        kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_abort_reason: %{
        name: :assert_abort_reason,
        kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_abort_caught: %{
        name: :assert_abort_caught,
        kind: :then,
        args: %{
          reason: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_safe_execute_result: %{
        name: :assert_safe_execute_result,
        kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil},
          reason: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      assert_partial_content: %{
        name: :assert_partial_content,
        kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
