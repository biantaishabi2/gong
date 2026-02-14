defmodule Gong.PartialJson do
  @moduledoc """
  增量 JSON 解析 — 解析不完整的 JSON 字符串。

  用于流式工具调用参数的实时解析：LLM 逐块输出 JSON，
  本模块在 JSON 不完整时自动补全闭合符号，尽可能解析出已有字段。
  """

  @doc """
  解析 JSON 字符串，支持不完整输入。

  返回值：
  - {:ok, map}     完整 JSON 成功解析
  - {:partial, map} 不完整 JSON 补全后解析
  - {:ok, %{}}     空输入
  - :error          无法解析
  """
  @spec parse(String.t()) :: {:ok, map()} | {:partial, map()} | :error
  def parse(input) when is_binary(input) do
    trimmed = String.trim(input)

    if trimmed == "" do
      {:ok, %{}}
    else
      # 快速路径：完整 JSON
      case Jason.decode(trimmed) do
        {:ok, result} when is_map(result) ->
          {:ok, result}

        {:ok, _other} ->
          {:ok, %{}}

        {:error, _} ->
          # 慢速路径：尝试补全
          try_complete(trimmed)
      end
    end
  end

  @doc """
  累积多个 JSON 片段，合并后解析。
  返回 {累积的缓冲区, 解析结果}。
  """
  @spec accumulate(String.t(), String.t()) :: {String.t(), map()}
  def accumulate(buffer, new_chunk) do
    combined = buffer <> new_chunk

    case parse(combined) do
      {:ok, result} -> {combined, result}
      {:partial, result} -> {combined, result}
      :error -> {combined, %{}}
    end
  end

  # ── 内部实现 ──

  defp try_complete(input) do
    # 移除尾部逗号
    cleaned = String.replace(input, ~r/,\s*$/, "")

    # 扫描未闭合的括号和引号
    closers = compute_closers(cleaned)
    completed = cleaned <> closers

    case Jason.decode(completed) do
      {:ok, result} when is_map(result) ->
        {:partial, result}

      _ ->
        # 最后尝试：截断到最后一个完整值
        try_truncate(cleaned)
    end
  end

  defp compute_closers(input) do
    input
    |> String.graphemes()
    |> Enum.reduce({[], false, false}, fn char, {stack, in_string, escaped} ->
      cond do
        escaped ->
          {stack, in_string, false}

        char == "\\" and in_string ->
          {stack, in_string, true}

        char == "\"" and not in_string ->
          {stack, true, false}

        char == "\"" and in_string ->
          {stack, false, false}

        in_string ->
          {stack, in_string, false}

        char == "{" ->
          {["}" | stack], false, false}

        char == "[" ->
          {["]" | stack], false, false}

        char == "}" ->
          {tl_safe(stack), false, false}

        char == "]" ->
          {tl_safe(stack), false, false}

        true ->
          {stack, false, false}
      end
    end)
    |> then(fn {stack, in_string, _escaped} ->
      prefix = if in_string, do: "\"", else: ""
      prefix <> Enum.join(stack)
    end)
  end

  defp tl_safe([_ | rest]), do: rest
  defp tl_safe([]), do: []

  defp try_truncate(input) do
    # 找到最后一个完整的 key:value 对的位置
    # 通过从后向前找逗号来截断
    case String.last(input) do
      ":" ->
        # 值还没开始，截掉最后的 key:
        truncated =
          input
          |> String.replace(~r/,?\s*"[^"]*"\s*:\s*$/, "")

        closers = compute_closers(truncated)
        completed = truncated <> closers

        case Jason.decode(completed) do
          {:ok, result} when is_map(result) -> {:partial, result}
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
