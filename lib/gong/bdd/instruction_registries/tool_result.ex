defmodule Gong.BDD.InstructionRegistries.ToolResult do
  @moduledoc "工具结果双通道 BDD 指令注册表"

  @base %{outputs: %{}, rules: [], boundary: :test_runtime, scopes: [:unit, :integration], async?: false, eventually?: false, assert_class: nil}

  def specs(:v1) do
    %{
      # WHEN
      tool_result_from_text: Map.merge(@base, %{name: :tool_result_from_text, kind: :when, args: %{text: %{type: :string, required?: true, allowed: nil}}}),
      tool_result_new: Map.merge(@base, %{name: :tool_result_new, kind: :when, args: %{content: %{type: :string, required?: true, allowed: nil}, details_key: %{type: :string, required?: true, allowed: nil}, details_value: %{type: :string, required?: true, allowed: nil}}}),
      tool_result_error: Map.merge(@base, %{name: :tool_result_error, kind: :when, args: %{content: %{type: :string, required?: true, allowed: nil}}}),

      # THEN
      assert_tool_result_content: Map.merge(@base, %{name: :assert_tool_result_content, kind: :then, args: %{contains: %{type: :string, required?: true, allowed: nil}}}),
      assert_tool_result_details_nil: Map.merge(@base, %{name: :assert_tool_result_details_nil, kind: :then, args: %{}}),
      assert_tool_result_has_details: Map.merge(@base, %{name: :assert_tool_result_has_details, kind: :then, args: %{key: %{type: :string, required?: true, allowed: nil}}}),
      assert_tool_result_details_value: Map.merge(@base, %{name: :assert_tool_result_details_value, kind: :then, args: %{key: %{type: :string, required?: true, allowed: nil}, expected: %{type: :string, required?: true, allowed: nil}}}),
      assert_tool_result_is_error: Map.merge(@base, %{name: :assert_tool_result_is_error, kind: :then, args: %{}}),
      assert_tool_result_not_error: Map.merge(@base, %{name: :assert_tool_result_not_error, kind: :then, args: %{}}),
      assert_is_tool_result: Map.merge(@base, %{name: :assert_is_tool_result, kind: :then, args: %{}})
    }
  end
end
