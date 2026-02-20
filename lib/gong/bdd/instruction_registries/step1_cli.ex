defmodule Gong.BDD.InstructionRegistries.Step1CLI do
  @moduledoc "Step1 CLI 交互层 BDD 指令注册（lookup_by_string / run_as_backend / stream callback / session backend）"

  def specs(:v1) do
    %{
      # ── ModelRegistry lookup_by_string ──

      lookup_model_by_string: %{
        name: :lookup_model_by_string, kind: :when,
        args: %{
          model_str: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_lookup_ok: %{
        name: :assert_lookup_ok, kind: :then,
        args: %{
          provider: %{type: :string, required?: false, allowed: nil},
          model_id: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_lookup_api_key_env: %{
        name: :assert_lookup_api_key_env, kind: :then,
        args: %{
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_lookup_error: %{
        name: :assert_lookup_error, kind: :then,
        args: %{
          error_type: %{type: :string, required?: false, allowed: nil},
          error_contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :error
      },

      # ── AgentLoop run_as_backend ──

      mock_reqllm_response: %{
        name: :mock_reqllm_response, kind: :given,
        args: %{
          model: %{type: :string, required?: false, allowed: nil},
          response_type: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: false, allowed: nil},
          tool: %{type: :string, required?: false, allowed: nil},
          tool_args: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      run_as_backend: %{
        name: :run_as_backend, kind: :when,
        args: %{
          message: %{type: :string, required?: true, allowed: nil},
          model_str: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_backend_reply: %{
        name: :assert_backend_reply, kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_backend_error: %{
        name: :assert_backend_error, kind: :then,
        args: %{
          error_contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :error
      },

      # ── Stream 回调 ──

      attach_stream_callback: %{
        name: :attach_stream_callback, kind: :given,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      clear_stream_callback: %{
        name: :clear_stream_callback, kind: :given,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_stream_callback_events: %{
        name: :assert_stream_callback_events, kind: :then,
        args: %{
          count: %{type: :int, required?: false, allowed: nil},
          types: %{type: :string, required?: false, allowed: nil},
          sequence: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_stream_callback_events_include: %{
        name: :assert_stream_callback_events_include, kind: :then,
        args: %{
          type: %{type: :string, required?: true, allowed: nil},
          tool_name: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_stream_callback_events_empty: %{
        name: :assert_stream_callback_events_empty, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },

      # ── Session backend 解析 ──

      init_session: %{
        name: :init_session, kind: :given,
        args: %{
          with_mock_backend: %{type: :string, required?: false, allowed: nil},
          with_model: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      session_prompt: %{
        name: :session_prompt, kind: :when,
        args: %{
          message: %{type: :string, required?: true, allowed: nil},
          model: %{type: :string, required?: false, allowed: nil},
          backend: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_session_reply: %{
        name: :assert_session_reply, kind: :then,
        args: %{
          contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      assert_session_backend_resolved: %{
        name: :assert_session_backend_resolved, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :C
      },
      init_session_expect_error: %{
        name: :init_session_expect_error, kind: :when,
        args: %{
          with_model: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil
      },
      assert_session_error: %{
        name: :assert_session_error, kind: :then,
        args: %{
          error_contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :service,
        scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: :error
      }
    }
  end

  def specs(:v2), do: %{}
end
