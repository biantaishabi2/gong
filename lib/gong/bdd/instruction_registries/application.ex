defmodule Gong.BDD.InstructionRegistries.Application do
  @moduledoc "Application 启动与监督的 BDD 指令"

  def specs(:v1) do
    %{
      # ══════════════════════════════════════════════════════
      # GIVEN 指令
      # ══════════════════════════════════════════════════════
      application_not_started: %{
        name: :application_not_started,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      application_started: %{
        name: :application_started,
        kind: :given,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ══════════════════════════════════════════════════════
      # WHEN 指令
      # ══════════════════════════════════════════════════════
      start_application: %{
        name: :start_application,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      start_application_catch: %{
        name: :start_application_catch,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      stop_application: %{
        name: :stop_application,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      create_session_via_supervisor: %{
        name: :create_session_via_supervisor,
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
      kill_session_process: %{
        name: :kill_session_process,
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
      try_register_duplicate_registry: %{
        name: :try_register_duplicate_registry,
        kind: :when,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      mock_registry_start_failure: %{
        name: :mock_registry_start_failure,
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

      # ══════════════════════════════════════════════════════
      # THEN 指令
      # ══════════════════════════════════════════════════════
      assert_registry_running: %{
        name: :assert_registry_running,
        kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_supervisor_running: %{
        name: :assert_supervisor_running,
        kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_ets_table_exists: %{
        name: :assert_ets_table_exists,
        kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_provider_registered: %{
        name: :assert_provider_registered,
        kind: :then,
        args: %{
          name: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_session_restarted: %{
        name: :assert_session_restarted,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_other_children_unchanged: %{
        name: :assert_other_children_unchanged,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_registry_error: %{
        name: :assert_registry_error,
        kind: :then,
        args: %{
          error_contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_no_session_processes: %{
        name: :assert_no_session_processes,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_no_registry_processes: %{
        name: :assert_no_registry_processes,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_application_already_started: %{
        name: :assert_application_already_started,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      },
      assert_start_failed: %{
        name: :assert_start_failed,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:integration],
        async?: false,
        eventually?: false,
        assert_class: :assertion
      }
    }
  end
end
