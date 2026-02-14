defmodule Gong.BDD.InstructionRegistries.Prompt do
  @moduledoc "Prompt 工程 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN ──

      prompt_messages_with_long_content: %{
        name: :prompt_messages_with_long_content,
        kind: :given,
        args: %{
          length: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      prompt_messages_plain: %{
        name: :prompt_messages_plain,
        kind: :given,
        args: %{
          count: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      prompt_messages_multi_tools: %{
        name: :prompt_messages_multi_tools,
        kind: :given,
        args: %{
          tools: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      prompt_messages_with_summary: %{
        name: :prompt_messages_with_summary,
        kind: :given,
        args: %{
          summary: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN ──

      build_default_prompt: %{
        name: :build_default_prompt,
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
      build_workspace_prompt: %{
        name: :build_workspace_prompt,
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
      format_conversation: %{
        name: :format_conversation,
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
      extract_prompt_file_ops: %{
        name: :extract_prompt_file_ops,
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
      find_previous_summary: %{
        name: :find_previous_summary,
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

      # ── THEN ──

      assert_prompt_text: %{
        name: :assert_prompt_text,
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
      assert_formatted_length: %{
        name: :assert_formatted_length,
        kind: :then,
        args: %{
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
      assert_file_ops_text: %{
        name: :assert_file_ops_text,
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
      assert_previous_summary: %{
        name: :assert_previous_summary,
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
      assert_previous_summary_nil: %{
        name: :assert_previous_summary_nil,
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
