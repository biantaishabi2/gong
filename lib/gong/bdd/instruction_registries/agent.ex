defmodule Gong.BDD.InstructionRegistries.Agent do
  @moduledoc "Agent 集成 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN: Agent 配置 ──

      configure_agent: %{
        name: :configure_agent,
        kind: :given,
        args: %{
          model: %{type: :string, required?: false, allowed: nil},
          tools: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      mock_llm_response: %{
        name: :mock_llm_response,
        kind: :given,
        args: %{
          response_type: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: false, allowed: nil},
          tool: %{type: :string, required?: false, allowed: nil},
          tool_args: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      register_hook: %{
        name: :register_hook,
        kind: :given,
        args: %{
          module: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN: Agent 操作 ──

      agent_chat: %{
        name: :agent_chat,
        kind: :when,
        args: %{
          prompt: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      agent_stream: %{
        name: :agent_stream,
        kind: :when,
        args: %{
          prompt: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :external_io,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      agent_abort: %{
        name: :agent_abort,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      trigger_compaction: %{
        name: :trigger_compaction,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: Agent 断言 ──

      assert_agent_reply: %{
        name: :assert_agent_reply,
        kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_tool_was_called: %{
        name: :assert_tool_was_called,
        kind: :then,
        args: %{
          tool: %{type: :string, required?: true, allowed: nil},
          times: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_tool_not_called: %{
        name: :assert_tool_not_called,
        kind: :then,
        args: %{
          tool: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_hook_fired: %{
        name: :assert_hook_fired,
        kind: :then,
        args: %{
          event: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_hook_blocked: %{
        name: :assert_hook_blocked,
        kind: :then,
        args: %{
          reason_contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_stream_events: %{
        name: :assert_stream_events,
        kind: :then,
        args: %{
          sequence: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration, :e2e],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_no_crash: %{
        name: :assert_no_crash,
        kind: :then,
        args: %{},
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
