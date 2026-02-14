defmodule Gong.BDD.InstructionRegistries.Compaction do
  @moduledoc "Compaction 压缩 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN 指令 ──

      compaction_messages: %{
        name: :compaction_messages,
        kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          token_size: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{compaction_messages: :list},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      compaction_messages_with_system: %{
        name: :compaction_messages_with_system,
        kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{compaction_messages: :list},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      compaction_lock_acquired: %{
        name: :compaction_lock_acquired,
        kind: :given,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      compaction_summarize_fn_ok: %{
        name: :compaction_summarize_fn_ok,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      compaction_summarize_fn_fail: %{
        name: :compaction_summarize_fn_fail,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      compaction_summarize_fn_raise: %{
        name: :compaction_summarize_fn_raise,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN 指令 ──

      when_estimate_tokens: %{
        name: :when_estimate_tokens,
        kind: :when,
        args: %{},
        outputs: %{token_estimate: :int},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_compact: %{
        name: :when_compact,
        kind: :when,
        args: %{
          max_tokens: %{type: :int, required?: false, allowed: nil},
          window_size: %{type: :int, required?: false, allowed: nil},
          context_window: %{type: :int, required?: false, allowed: nil},
          reserve_tokens: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_compact_and_handoff: %{
        name: :when_compact_and_handoff,
        kind: :when,
        args: %{
          max_tokens: %{type: :int, required?: false, allowed: nil},
          window_size: %{type: :int, required?: false, allowed: nil},
          context_window: %{type: :int, required?: false, allowed: nil},
          reserve_tokens: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_acquire_lock: %{
        name: :when_acquire_lock,
        kind: :when,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      when_release_lock: %{
        name: :when_release_lock,
        kind: :when,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN 指令 ──

      assert_token_estimate: %{
        name: :assert_token_estimate,
        kind: :then,
        args: %{
          min: %{type: :int, required?: true, allowed: nil},
          max: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_compacted: %{
        name: :assert_compacted,
        kind: :then,
        args: %{
          message_count: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_not_compacted: %{
        name: :assert_not_compacted,
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
      assert_summary_exists: %{
        name: :assert_summary_exists,
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
      assert_summary_nil: %{
        name: :assert_summary_nil,
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
      assert_system_preserved: %{
        name: :assert_system_preserved,
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
      assert_compaction_error: %{
        name: :assert_compaction_error,
        kind: :then,
        args: %{
          error_contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :error
      },
      assert_no_compaction_error: %{
        name: :assert_no_compaction_error,
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
      assert_tape_has_compaction_anchor: %{
        name: :assert_tape_has_compaction_anchor,
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

      # ── Lock 并发 & Token 精度 ──

      concurrent_lock_acquire: %{
        name: :concurrent_lock_acquire,
        kind: :when,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil},
          tasks: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_lock_race_result: %{
        name: :assert_lock_race_result,
        kind: :then,
        args: %{
          winners: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      estimate_text: %{
        name: :estimate_text,
        kind: :when,
        args: %{
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_token_estimate_value: %{
        name: :assert_token_estimate_value,
        kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── Session header 边界 + 工具调用摘要 + 跨模型 overflow ──
      compaction_messages_with_session_header: %{
        name: :compaction_messages_with_session_header, kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          header_at: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_session_header_preserved: %{
        name: :assert_session_header_preserved, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      compact_with_tool_calls: %{
        name: :compact_with_tool_calls, kind: :when,
        args: %{
          max_tokens: %{type: :int, required?: true, allowed: nil},
          window_size: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_summary_has_tool_calls: %{
        name: :assert_summary_has_tool_calls, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      trigger_overflow_on_model: %{
        name: :trigger_overflow_on_model, kind: :when,
        args: %{model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      switch_model_after_overflow: %{
        name: :switch_model_after_overflow, kind: :when,
        args: %{new_model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_no_compaction_on_new_model: %{
        name: :assert_no_compaction_on_new_model, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
