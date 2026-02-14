defmodule Gong.CrossProvider do
  @moduledoc """
  跨 Provider 上下文保持 — 在 Provider 切换时转换消息格式。

  不同 Provider 的消息格式略有差异（tool_calls、system message 处理等），
  此模块负责消息在 Provider 间的兼容转换。
  """

  @doc "转换消息列表到目标 provider 格式"
  @spec convert_messages([map()], String.t(), String.t()) :: [map()]
  def convert_messages(messages, from_provider, to_provider) when is_list(messages) do
    Enum.map(messages, &convert_message(&1, from_provider, to_provider))
  end

  @doc "转换单条消息"
  @spec convert_message(map(), String.t(), String.t()) :: map()
  def convert_message(msg, _from, _to) when is_map(msg) do
    msg
    |> normalize_role()
    |> normalize_content()
    |> normalize_tool_calls()
  end

  @doc "构建切换上下文摘要"
  @spec build_handoff_summary([map()]) :: String.t()
  def build_handoff_summary(messages) when is_list(messages) do
    recent = Enum.take(messages, -5)

    recent
    |> Enum.map(fn msg ->
      role = Map.get(msg, :role, Map.get(msg, "role", "unknown"))
      content = Map.get(msg, :content, Map.get(msg, "content", ""))
      "[#{role}] #{String.slice(to_string(content), 0, 100)}"
    end)
    |> Enum.join("\n")
  end

  # 角色名规范化
  defp normalize_role(%{role: role} = msg) when role in ["system", "user", "assistant", "tool"], do: msg
  defp normalize_role(%{"role" => role} = msg) when role in ["system", "user", "assistant", "tool"] do
    msg |> Map.delete("role") |> Map.put(:role, role)
  end
  defp normalize_role(msg), do: msg

  # 内容格式规范化
  defp normalize_content(%{content: content} = msg) when is_list(content) do
    # 多部分内容转换为纯文本
    text = Enum.map_join(content, "\n", fn
      %{type: "text", text: t} -> t
      %{"type" => "text", "text" => t} -> t
      _ -> ""
    end)
    %{msg | content: text}
  end
  defp normalize_content(msg), do: msg

  # 工具调用格式规范化
  defp normalize_tool_calls(%{tool_calls: calls} = msg) when is_list(calls) do
    normalized = Enum.map(calls, fn tc ->
      %{
        id: Map.get(tc, :id, Map.get(tc, "id", "tc_#{System.unique_integer([:positive])}")),
        name: Map.get(tc, :name, Map.get(tc, "name", "")),
        arguments: Map.get(tc, :arguments, Map.get(tc, "arguments", %{}))
      }
    end)
    %{msg | tool_calls: normalized}
  end
  defp normalize_tool_calls(msg), do: msg
end
