defmodule Gong.BDD.InstructionRegistries.PartialJson do
  @moduledoc "增量 JSON 解析 BDD 指令注册表"

  @base %{outputs: %{}, rules: [], boundary: :test_runtime, scopes: [:unit], async?: false, eventually?: false, assert_class: nil}

  def specs(:v1) do
    %{
      # WHEN
      partial_json_parse: Map.merge(@base, %{name: :partial_json_parse, kind: :when, args: %{input: %{type: :string, required?: true, allowed: nil}}}),
      partial_json_accumulate: Map.merge(@base, %{name: :partial_json_accumulate, kind: :when, args: %{chunk1: %{type: :string, required?: true, allowed: nil}, chunk2: %{type: :string, required?: true, allowed: nil}, chunk3: %{type: :string, required?: true, allowed: nil}}}),

      # THEN
      assert_partial_json_ok: Map.merge(@base, %{name: :assert_partial_json_ok, kind: :then, args: %{}}),
      assert_partial_json_field: Map.merge(@base, %{name: :assert_partial_json_field, kind: :then, args: %{key: %{type: :string, required?: true, allowed: nil}, expected: %{type: :string, required?: true, allowed: nil}}}),
      assert_partial_json_has_key: Map.merge(@base, %{name: :assert_partial_json_has_key, kind: :then, args: %{key: %{type: :string, required?: true, allowed: nil}}}),
      assert_partial_json_empty: Map.merge(@base, %{name: :assert_partial_json_empty, kind: :then, args: %{}}),
    }
  end
end
