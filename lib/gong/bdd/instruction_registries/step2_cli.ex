defmodule Gong.BDD.InstructionRegistries.Step2CLI do
  @moduledoc "Step2 CLI 交互层 BDD 指令注册（命令解析 / Renderer / Run / Chat）"

  def specs(:v1) do
    %{
      # ── Group 1: 命令解析 ──

      cli_parse: %{
        name: :cli_parse, kind: :when,
        args: %{
          argv: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      cli_run: %{
        name: :cli_run, kind: :when,
        args: %{
          argv: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      assert_cli_command: %{
        name: :assert_cli_command, kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_cli_opt: %{
        name: :assert_cli_opt, kind: :then,
        args: %{
          key: %{type: :string, required?: true, allowed: nil},
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_cli_prompt: %{
        name: :assert_cli_prompt, kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_cli_session_id: %{
        name: :assert_cli_session_id, kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_cli_exit_code: %{
        name: :assert_cli_exit_code, kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── Group 2: Renderer ──

      capture_io: %{
        name: :capture_io, kind: :given,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      render_event: %{
        name: :render_event, kind: :when,
        args: %{
          type: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: false, allowed: nil},
          tool_name: %{type: :string, required?: false, allowed: nil},
          tool_args: %{type: :string, required?: false, allowed: nil},
          result: %{type: :string, required?: false, allowed: nil},
          message: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_io_output: %{
        name: :assert_io_output, kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: :C
      },
      assert_io_output_empty: %{
        name: :assert_io_output_empty, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_io_output_max_length: %{
        name: :assert_io_output_max_length, kind: :then,
        args: %{
          max: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_stderr_output: %{
        name: :assert_stderr_output, kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── Group 3: Run ──

      cli_run_prompt: %{
        name: :cli_run_prompt, kind: :when,
        args: %{
          prompt: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_cli_output: %{
        name: :assert_cli_output, kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── Group 4: Chat ──

      start_chat_session: %{
        name: :start_chat_session, kind: :given,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      chat_input: %{
        name: :chat_input, kind: :when,
        args: %{
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      chat_wait_completion: %{
        name: :chat_wait_completion, kind: :when,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      assert_session_closed: %{
        name: :assert_session_closed, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_no_agent_call: %{
        name: :assert_no_agent_call, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── Step3/4 占位 spec（仅注册以让 bddc 编译通过）──

      cli_session_list: %{
        name: :cli_session_list, kind: :when,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      cli_session_restore: %{
        name: :cli_session_restore, kind: :when,
        args: %{
          session_id: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      chat_session_restore: %{
        name: :chat_session_restore, kind: :when,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      tape_save_session: %{
        name: :tape_save_session, kind: :given,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: nil
      },
      assert_session_list_count: %{
        name: :assert_session_list_count, kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_session_list_contains: %{
        name: :assert_session_list_contains, kind: :then,
        args: %{
          session_id: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_session_restored: %{
        name: :assert_session_restored, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: :C
      },
      assert_session_history_contains: %{
        name: :assert_session_history_contains, kind: :then,
        args: %{
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: :C
      },
      assert_session_restore_error: %{
        name: :assert_session_restore_error, kind: :then,
        args: %{
          error_contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :error
      },
      assert_session_saved: %{
        name: :assert_session_saved, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration, :e2e], async?: false, eventually?: false, assert_class: :C
      },

      # ── Session 容错 ──

      create_corrupt_session_file: %{
        name: :create_corrupt_session_file, kind: :given,
        args: %{
          filename: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      }
    }
  end

  def specs(:v2), do: %{}
end
