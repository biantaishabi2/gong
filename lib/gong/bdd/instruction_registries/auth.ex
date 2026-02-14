defmodule Gong.BDD.InstructionRegistries.Auth do
  @moduledoc "Auth OAuth BDD 指令注册"

  def specs(:v1) do
    %{
      detect_auth_method: %{
        name: :detect_auth_method, kind: :when,
        args: %{provider: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      generate_authorize_url: %{
        name: :generate_authorize_url, kind: :when,
        args: %{
          client_id: %{type: :string, required?: true, allowed: nil},
          authorize_url: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      exchange_auth_code: %{
        name: :exchange_auth_code, kind: :when,
        args: %{code: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_auth_method: %{
        name: :assert_auth_method, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_authorize_url: %{
        name: :assert_authorize_url, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_auth_token: %{
        name: :assert_auth_token, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 补充覆盖 ──
      refresh_auth_token: %{
        name: :refresh_auth_token, kind: :when,
        args: %{refresh: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      check_token_expired: %{
        name: :check_token_expired, kind: :when,
        args: %{expires_at: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_token_expired: %{
        name: :assert_token_expired, kind: :then,
        args: %{expected: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      get_api_key: %{
        name: :get_api_key, kind: :when,
        args: %{env_var: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_api_key_result: %{
        name: :assert_api_key_result, kind: :then,
        args: %{status: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },

      # ── 认证锁文件 ──
      create_auth_lock_file: %{
        name: :create_auth_lock_file, kind: :given,
        args: %{content: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      corrupt_auth_lock_file: %{
        name: :corrupt_auth_lock_file, kind: :given,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_auth_lock_recovered: %{
        name: :assert_auth_lock_recovered, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      set_env_api_key: %{
        name: :set_env_api_key, kind: :given,
        args: %{
          env_var: %{type: :string, required?: true, allowed: nil},
          value: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      get_api_key_via_auth: %{
        name: :get_api_key_via_auth, kind: :when,
        args: %{env_var: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_env_unchanged: %{
        name: :assert_env_unchanged, kind: :then,
        args: %{
          env_var: %{type: :string, required?: true, allowed: nil},
          expected: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      auth_logout: %{
        name: :auth_logout, kind: :when,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_model_references_cleaned: %{
        name: :assert_model_references_cleaned, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      create_expiring_token: %{
        name: :create_expiring_token, kind: :given,
        args: %{expires_in_seconds: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      simulate_token_check: %{
        name: :simulate_token_check, kind: :when,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_token_refreshed: %{
        name: :assert_token_refreshed, kind: :then,
        args: %{},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
