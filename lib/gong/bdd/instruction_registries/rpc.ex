defmodule Gong.BDD.InstructionRegistries.RPC do
  @moduledoc "RPC 模式 BDD 指令注册"

  def specs(:v1) do
    %{
      parse_rpc_request: %{
        name: :parse_rpc_request, kind: :when,
        args: %{json: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      rpc_dispatch: %{
        name: :rpc_dispatch, kind: :when,
        args: %{
          method: %{type: :string, required?: true, allowed: nil},
          params: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      rpc_dispatch_missing: %{
        name: :rpc_dispatch_missing, kind: :when,
        args: %{method: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      rpc_handle: %{
        name: :rpc_handle, kind: :when,
        args: %{json: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: nil
      },
      assert_rpc_parsed: %{
        name: :assert_rpc_parsed, kind: :then,
        args: %{method: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_rpc_error: %{
        name: :assert_rpc_error, kind: :then,
        args: %{code: %{type: :int, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :error
      },
      assert_rpc_result: %{
        name: :assert_rpc_result, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      },
      assert_rpc_response_json: %{
        name: :assert_rpc_response_json, kind: :then,
        args: %{contains: %{type: :string, required?: true, allowed: nil}},
        outputs: %{}, rules: [], boundary: :test_runtime,
        scopes: [:unit], async?: false, eventually?: false, assert_class: :C
      }
    }
  end

  def specs(:v2), do: %{}
end
