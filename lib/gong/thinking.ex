defmodule Gong.Thinking do
  @moduledoc """
  Thinking/Reasoning 预算管理。

  支持 6 级 thinking level 控制：off → low → medium → high → xhigh → max。
  跨 provider 统一接口。
  """

  @type level :: :off | :low | :medium | :high | :xhigh | :max

  @levels [:off, :low, :medium, :high, :xhigh, :max]
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

  @doc "从字符串解析 level"
  @spec parse(String.t()) :: {:ok, level()} | {:error, :invalid_level}
  def parse(str) when is_binary(str) do
    atom = String.to_existing_atom(str)
    if valid_level?(atom), do: {:ok, atom}, else: {:error, :invalid_level}
  rescue
    ArgumentError -> {:error, :invalid_level}
  end

  # 内部：OpenAI reasoning_effort 映射
  defp level_to_effort(:low), do: "low"
  defp level_to_effort(:medium), do: "medium"
  defp level_to_effort(:high), do: "high"
  defp level_to_effort(:xhigh), do: "high"
  defp level_to_effort(:max), do: "high"
end
