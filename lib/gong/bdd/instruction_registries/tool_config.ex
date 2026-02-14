defmodule Gong.BDD.InstructionRegistries.ToolConfig do
  @moduledoc "工具配置系统 BDD 指令注册表"

  @base %{outputs: %{}, rules: [], boundary: :test_runtime, scopes: [:unit], async?: false, eventually?: false, assert_class: nil}

  def specs(:v1) do
    %{
      # GIVEN
      init_tool_config: Map.merge(@base, %{name: :init_tool_config, kind: :given, args: %{}}),

      # WHEN
      get_active_tools: Map.merge(@base, %{name: :get_active_tools, kind: :when, args: %{}}),
      get_preset: Map.merge(@base, %{name: :get_preset, kind: :when, args: %{name: %{type: :string, required?: true, allowed: nil}}}),
      set_active_tools: Map.merge(@base, %{name: :set_active_tools, kind: :when, args: %{tools: %{type: :string, required?: true, allowed: nil}}}),
      set_active_tools_safe: Map.merge(@base, %{name: :set_active_tools_safe, kind: :when, args: %{tools: %{type: :string, required?: true, allowed: nil}}}),
      validate_tools: Map.merge(@base, %{name: :validate_tools, kind: :when, args: %{tools: %{type: :string, required?: true, allowed: nil}}}),

      # THEN
      assert_active_tool_count: Map.merge(@base, %{name: :assert_active_tool_count, kind: :then, args: %{expected: %{type: :int, required?: true, allowed: nil}}}),
      assert_active_tool_contains: Map.merge(@base, %{name: :assert_active_tool_contains, kind: :then, args: %{tool: %{type: :string, required?: true, allowed: nil}}}),
      assert_preset_contains: Map.merge(@base, %{name: :assert_preset_contains, kind: :then, args: %{tool: %{type: :string, required?: true, allowed: nil}}}),
      assert_preset_not_contains: Map.merge(@base, %{name: :assert_preset_not_contains, kind: :then, args: %{tool: %{type: :string, required?: true, allowed: nil}}}),
      assert_preset_count: Map.merge(@base, %{name: :assert_preset_count, kind: :then, args: %{expected: %{type: :int, required?: true, allowed: nil}}}),
      assert_tool_config_error: Map.merge(@base, %{name: :assert_tool_config_error, kind: :then, args: %{contains: %{type: :string, required?: true, allowed: nil}}})
    }
  end
end
