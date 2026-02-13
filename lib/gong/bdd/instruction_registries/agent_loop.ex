defmodule Gong.BDD.InstructionRegistries.AgentLoop do
  @moduledoc "Agent 循环扩展 BDD 指令：Steering + Retry + Compaction 配对保护"

  def specs(:v1) do
    %{
      # ── GIVEN: Steering ──

      steering_queue_empty: %{
        name: :steering_queue_empty,
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

      # ── WHEN: Steering ──

      steering_push: %{
        name: :steering_push,
        kind: :when,
        args: %{
          message: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      steering_check: %{
        name: :steering_check,
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
      steering_skip_result: %{
        name: :steering_skip_result,
        kind: :when,
        args: %{
          tool: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Steering ──

      assert_steering_pending: %{
        name: :assert_steering_pending,
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
      assert_steering_empty: %{
        name: :assert_steering_empty,
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
      assert_steering_message: %{
        name: :assert_steering_message,
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
      assert_steering_skip_contains: %{
        name: :assert_steering_skip_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── WHEN: Retry ──

      classify_error: %{
        name: :classify_error,
        kind: :when,
        args: %{
          error: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      retry_delay: %{
        name: :retry_delay,
        kind: :when,
        args: %{
          attempt: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      retry_should_retry: %{
        name: :retry_should_retry,
        kind: :when,
        args: %{
          error_class: %{type: :string, required?: true, allowed: nil},
          attempt: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Retry ──

      assert_error_class: %{
        name: :assert_error_class,
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
      assert_delay_ms: %{
        name: :assert_delay_ms,
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
      assert_should_retry: %{
        name: :assert_should_retry,
        kind: :then,
        args: %{
          expected: %{type: :bool, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── GIVEN: Compaction 配对保护 ──

      compaction_messages_with_tools: %{
        name: :compaction_messages_with_tools,
        kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          tool_pair_at: %{type: :int, required?: true, allowed: nil},
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

      # ── THEN: Compaction 配对保护 ──

      assert_tool_pairs_intact: %{
        name: :assert_tool_pairs_intact,
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

      # ── GIVEN: 结构化摘要 ──

      compaction_messages_with_tool_calls: %{
        name: :compaction_messages_with_tool_calls,
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
      compaction_messages_with_summary: %{
        name: :compaction_messages_with_summary,
        kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          summary: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{compaction_messages: :list},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN: 结构化摘要 ──

      build_summarize_prompt: %{
        name: :build_summarize_prompt,
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
      extract_file_operations: %{
        name: :extract_file_operations,
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

      # ── THEN: 结构化摘要 ──

      assert_prompt_contains: %{
        name: :assert_prompt_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_prompt_mode: %{
        name: :assert_prompt_mode,
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
      assert_file_ops_contains: %{
        name: :assert_file_ops_contains,
        kind: :then,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      },

      # ── WHEN: Auto-Compaction ──

      auto_compact: %{
        name: :auto_compact,
        kind: :when,
        args: %{
          context_window: %{type: :int, required?: true, allowed: nil},
          reserve_tokens: %{type: :int, required?: true, allowed: nil},
          window_size: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Auto-Compaction ──

      assert_auto_compacted: %{
        name: :assert_auto_compacted,
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
      assert_auto_no_action: %{
        name: :assert_auto_no_action,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
