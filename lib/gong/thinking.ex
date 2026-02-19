defmodule Gong.Thinking do
  @moduledoc """
  Thinking/Reasoning 预算管理。

  支持 6 级 thinking level 控制：off → low → medium → high → xhigh → max。
  跨 provider 统一接口。
  """

  @type level :: :off | :low | :medium | :high | :xhigh | :max

  @levels [:off, :low, :medium, :high, :xhigh, :max]
  @default_level :off
  @level_tokens %{
    "off" => :off,
    "none" => :off,
    "disabled" => :off,
    "low" => :low,
    "medium" => :medium,
    "high" => :high,
    "xhigh" => :xhigh,
    "x-high" => :xhigh,
    "max" => :max
  }
  @level_by_index %{0 => :off, 1 => :low, 2 => :medium, 3 => :high, 4 => :xhigh, 5 => :max}
  @level_budgets %{
    off: 0,
    low: 1024,
    medium: 4096,
    high: 8192,
    xhigh: 16384,
    max: 32768
  }

  @doc "所有支持的 thinking level"
  @spec levels() :: [level()]
  def levels, do: @levels

  @doc "默认 thinking level"
  @spec default_level() :: level()
  def default_level, do: @default_level

  @doc "验证 level 是否有效"
  @spec valid_level?(term()) :: boolean()
  def valid_level?(level) when level in @levels, do: true
  def valid_level?(_), do: false

  @doc "获取 level 对应的 token 预算"
  @spec budget(level()) :: non_neg_integer()
  def budget(level) when level in @levels do
    Map.fetch!(@level_budgets, level)
  end

  @doc "将 level 转换为 provider 特定参数"
  @spec to_provider_params(level(), String.t()) :: map()
  def to_provider_params(:off, _provider), do: %{}

  def to_provider_params(level, "anthropic") when level in @levels do
    %{thinking: %{type: "enabled", budget_tokens: budget(level)}}
  end

  def to_provider_params(level, "openai") when level in @levels do
    %{reasoning_effort: level_to_effort(level)}
  end

  def to_provider_params(level, "deepseek") when level in @levels do
    %{thinking_budget: budget(level)}
  end

  def to_provider_params(level, _provider) when level in @levels do
    %{thinking_budget: budget(level)}
  end

  @doc """
  兼容恢复：优先使用新字段，失败时回退旧字段，再回退默认值。
  """
  @spec restore_level(term(), term(), level()) :: {level(), :new | :legacy | :default}
  def restore_level(new_value, legacy_value, fallback \\ @default_level) do
    case normalize_level(new_value) do
      {:ok, level} ->
        {level, :new}

      {:error, :invalid_level} ->
        case normalize_level(legacy_value) do
          {:ok, level} -> {level, :legacy}
          {:error, :invalid_level} -> {fallback, :default}
        end
    end
  end

  @doc "规范化任意输入为合法 thinking level"
  @spec normalize_level(term()) :: {:ok, level()} | {:error, :invalid_level}
  def normalize_level(level) when is_atom(level) do
    if valid_level?(level), do: {:ok, level}, else: {:error, :invalid_level}
  end

  def normalize_level(level) when is_integer(level) do
    case Map.get(@level_by_index, level) do
      nil -> {:error, :invalid_level}
      normalized -> {:ok, normalized}
    end
  end

  def normalize_level(level) when is_binary(level) do
    level
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@level_tokens, &1))
    |> case do
      nil -> {:error, :invalid_level}
      normalized -> {:ok, normalized}
    end
  end

  def normalize_level(%{} = level_map) do
    candidate =
      Map.get(level_map, :level) ||
        Map.get(level_map, "level") ||
        Map.get(level_map, :thinking_level) ||
        Map.get(level_map, "thinking_level") ||
        Map.get(level_map, :thinkingLevel) ||
        Map.get(level_map, "thinkingLevel")

    normalize_level(candidate)
  end

  def normalize_level(_), do: {:error, :invalid_level}

  @doc "从字符串解析 level"
  @spec parse(String.t()) :: {:ok, level()} | {:error, :invalid_level}
  def parse(str) when is_binary(str) do
    normalize_level(str)
  end

  # 内部：OpenAI reasoning_effort 映射
  defp level_to_effort(:low), do: "low"
  defp level_to_effort(:medium), do: "medium"
  defp level_to_effort(:high), do: "high"
  defp level_to_effort(:xhigh), do: "high"
  defp level_to_effort(:max), do: "high"
end
