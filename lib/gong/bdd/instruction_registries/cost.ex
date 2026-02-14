defmodule Gong.BDD.InstructionRegistries.Cost do
  @moduledoc "Cost 追踪 BDD 指令注册"

  def specs(:v1) do
    %{
      init_cost_tracker: %{
        name: :init_cost_tracker, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      record_llm_call: %{
        name: :record_llm_call, kind: :when,
        args: %{
          model: %{type: :string, required?: true, allowed: nil},
          input_tokens: %{type: :int, required?: true, allowed: nil},
          output_tokens: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      reset_cost_tracker: %{
        name: :reset_cost_tracker, kind: :when,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_cost_summary: %{
        name: :assert_cost_summary, kind: :then,
        args: %{
          call_count: %{type: :int, required?: true, allowed: nil},
          total_input: %{type: :int, required?: false, allowed: nil},
          total_output: %{type: :int, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_last_call: %{
        name: :assert_last_call, kind: :then,
        args: %{model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 补充覆盖 ──
      assert_cost_history: %{
        name: :assert_cost_history, kind: :then,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          first_model: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_last_call_nil: %{
        name: :assert_last_call_nil, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 流中断部分令牌 ──
      record_partial_llm_call: %{
        name: :record_partial_llm_call, kind: :when,
        args: %{
          model: %{type: :string, required?: true, allowed: nil},
          input_tokens: %{type: :int, required?: true, allowed: nil},
          output_tokens: %{type: :int, required?: true, allowed: nil},
          reason: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_partial_tokens_preserved: %{
        name: :assert_partial_tokens_preserved, kind: :then,
        args: %{model: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_cost_includes_partial: %{
        name: :assert_cost_includes_partial, kind: :then,
        args: %{}, outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
