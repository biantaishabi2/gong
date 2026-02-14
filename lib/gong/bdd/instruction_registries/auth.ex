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
      }
    }
  end

  def specs(:v2), do: %{}
end
