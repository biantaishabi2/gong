defmodule Gong.CLI.ToolDisplay do
  @moduledoc "工具参数友好显示 — 按约定参数名自动提取关键信息"

  # 按优先级排列：优先显示 file_path，其次 command，再 pattern/path
  @display_keys ~w(file_path command pattern path)a

  @spec format(String.t() | atom(), term()) :: String.t()
  def format(_tool_name, args) when is_map(args) and map_size(args) == 0, do: ""

  def format(_tool_name, args) when is_map(args) do
    case find_display_value(args) do
      nil -> Jason.encode!(args)
      val -> to_string(val)
    end
  end

  def format(_tool_name, args) when is_binary(args), do: args
  def format(_tool_name, args), do: inspect(args)

  defp find_display_value(args) do
    Enum.find_value(@display_keys, fn key ->
      Map.get(args, key) || Map.get(args, Atom.to_string(key))
    end)
  end
end
