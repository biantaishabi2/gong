defmodule Gong.BDD.InstructionRegistries.Tape do
  @moduledoc "Tape 存储 BDD 指令注册"

  def specs(:v1) do
    %{
      # ── GIVEN 指令 ──

      tape_init: %{
        name: :tape_init,
        kind: :given,
        args: %{},
        outputs: %{tape_store: :struct},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tape_append: %{
        name: :tape_append,
        kind: :given,
        args: %{
          anchor: %{type: :string, required?: false, allowed: nil},
          kind: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tape_handoff: %{
        name: :tape_handoff,
        kind: :given,
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
      tape_fork: %{
        name: :tape_fork,
        kind: :given,
        args: %{},
        outputs: %{fork_store: :struct},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      tape_close_db: %{
        name: :tape_close_db,
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
      tape_restore_parent: %{
        name: :tape_restore_parent,
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
      corrupt_jsonl: %{
        name: :corrupt_jsonl,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          line_content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      delete_file: %{
        name: :delete_file,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      clear_file: %{
        name: :clear_file,
        kind: :given,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },

      # ── WHEN 指令 ──

      when_tape_init: %{
        name: :when_tape_init,
        kind: :when,
        args: %{},
        outputs: %{tape_store: :struct},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_tape_append: %{
        name: :when_tape_append,
        kind: :when,
        args: %{
          anchor: %{type: :string, required?: false, allowed: nil},
          kind: %{type: :string, required?: true, allowed: nil},
          content: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_tape_handoff: %{
        name: :when_tape_handoff,
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
      when_tape_between_anchors: %{
        name: :when_tape_between_anchors,
        kind: :when,
        args: %{
          start: %{type: :string, required?: true, allowed: nil},
          end: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_tape_search: %{
        name: :when_tape_search,
        kind: :when,
        args: %{
          query: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_tape_fork: %{
        name: :when_tape_fork,
        kind: :when,
        args: %{},
        outputs: %{fork_store: :struct},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      when_tape_merge: %{
        name: :when_tape_merge,
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
      when_tape_rebuild_index: %{
        name: :when_tape_rebuild_index,
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

      # ── THEN 指令 ──

      assert_dir_exists: %{
        name: :assert_dir_exists,
        kind: :then,
        args: %{
          path: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_db_exists: %{
        name: :assert_db_exists,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_entry_count: %{
        name: :assert_entry_count,
        kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_anchor_count: %{
        name: :assert_anchor_count,
        kind: :then,
        args: %{
          expected: %{type: :int, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_jsonl_contains: %{
        name: :assert_jsonl_contains,
        kind: :then,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_jsonl_not_contains: %{
        name: :assert_jsonl_not_contains,
        kind: :then,
        args: %{
          path: %{type: :string, required?: true, allowed: nil},
          text: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_query_results: %{
        name: :assert_query_results,
        kind: :then,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_search_results: %{
        name: :assert_search_results,
        kind: :then,
        args: %{
          count: %{type: :int, required?: true, allowed: nil},
          contains: %{type: :string, required?: false, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_tape_error: %{
        name: :assert_tape_error,
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
        assert_class: :error
      },
      assert_fork_cleaned: %{
        name: :assert_fork_cleaned,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
