defmodule Gong.BDD.InstructionRegistries.Stream do
  @moduledoc "Stream 流式输出 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN: 流式配置 ──

      mock_stream_response: %{
        name: :mock_stream_response,
        kind: :given,
        args: %{
          chunks: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── THEN: 流式断言 ──

      assert_stream_content: %{
        name: :assert_stream_content,
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
      },

      # ── 补充覆盖：tool 事件 ──
      stream_tool_chunks: %{
        name: :stream_tool_chunks, kind: :when,
        args: %{
          tool_name: %{type: :string, required?: true, allowed: nil},
          chunks: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_tool_event_sequence: %{
        name: :assert_tool_event_sequence, kind: :then,
        args: %{sequence: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_tool_event_name: %{
        name: :assert_tool_event_name, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 事件序列验证 ──
      validate_stream_events: %{
        name: :validate_stream_events, kind: :when,
        args: %{types: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_sequence_valid: %{
        name: :assert_sequence_valid, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_sequence_invalid: %{
        name: :assert_sequence_invalid, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 流式并发安全 ──
      start_mock_stream: %{
        name: :start_mock_stream, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      execute_hook_during_stream: %{
        name: :execute_hook_during_stream, kind: :when,
        args: %{hook_module: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_no_race_condition: %{
        name: :assert_no_race_condition, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 流式缓冲 ──
      buffer_tool_result_during_stream: %{
        name: :buffer_tool_result_during_stream, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_tool_result_buffered: %{
        name: :assert_tool_result_buffered, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
