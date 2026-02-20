defmodule Gong.CLI.Renderer do
  @moduledoc """
  终端渲染器 — 将 Session 事件流格式化输出到终端。
  """

  alias Gong.Session.Events

  @max_tool_args_length 80
  @max_result_length 200

  @doc """
  渲染单条 Session 事件到终端。

  事件映射:
  - `"message.delta"` → IO.write(payload.delta)
  - `"message.end"` → IO.write("\\n")
  - `"tool.start"` → 打印工具名和截断参数
  - `"tool.end"` → 打印截断结果
  - `"error.stream"` / `"error.runtime"` → stderr 输出
  - 其他 → :noop
  """
  @spec render(Events.t()) :: :ok
  def render(%Events{type: "message.delta", payload: payload}) do
    content = Map.get(payload, :content) || Map.get(payload, "content") || ""
    IO.write(content)
  end

  def render(%Events{type: "message.end"}) do
    IO.write("\n")
  end

  def render(%Events{type: "tool.start", payload: payload}) do
    tool_name = Map.get(payload, :tool_name) || Map.get(payload, "tool_name") || "unknown"
    tool_args = Map.get(payload, :tool_args) || Map.get(payload, "tool_args") || %{}

    args_str =
      case tool_args do
        s when is_binary(s) -> s
        m when is_map(m) -> Jason.encode!(m)
        other -> inspect(other)
      end

    IO.puts("[工具] #{tool_name}(#{truncate(args_str, @max_tool_args_length)})")
  end

  def render(%Events{type: "tool.end", payload: payload}) do
    result = Map.get(payload, :result) || Map.get(payload, "result") || ""

    result_str =
      case result do
        s when is_binary(s) -> s
        other -> inspect(other)
      end

    IO.puts("[结果] #{truncate(result_str, @max_result_length)}")
  end

  def render(%Events{type: type, payload: payload}) when type in ["error.stream", "error.runtime"] do
    message =
      Map.get(payload, :message) || Map.get(payload, "message") ||
        get_in_error(payload) || "未知错误"

    IO.puts(:stderr, "[错误] #{message}")
  end

  def render(%Events{}) do
    :ok
  end

  # 从 error 嵌套结构中提取 message
  defp get_in_error(payload) do
    error = Map.get(payload, :error) || Map.get(payload, "error")
    if is_map(error), do: Map.get(error, :message) || Map.get(error, "message")
  end

  @doc "截断字符串到指定最大长度"
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(str, max) when byte_size(str) <= max, do: str

  def truncate(str, max) do
    String.slice(str, 0, max) <> "..."
  end
end
