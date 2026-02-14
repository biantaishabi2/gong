defmodule Gong.PromptTemplate do
  @moduledoc """
  Prompt 模板系统 — 支持可扩展的 /templatename 提示模板。

  内置模板 + 自定义模板注册。
  """

  @table :gong_prompt_templates

  @type template :: %{
          name: String.t(),
          content: String.t(),
          description: String.t(),
          variables: [String.t()]
        }

  @builtin_templates %{
    "code_review" => %{
      name: "code_review",
      content: "请审查以下代码，关注：\n1. 逻辑错误\n2. 安全漏洞\n3. 性能问题\n4. 代码风格\n\n{{code}}",
      description: "代码审查模板",
      variables: ["code"]
    },
    "explain" => %{
      name: "explain",
      content: "请解释以下代码的功能和实现原理：\n\n{{code}}",
      description: "代码解释模板",
      variables: ["code"]
    },
    "refactor" => %{
      name: "refactor",
      content: "请重构以下代码，改善可读性和性能：\n\n{{code}}",
      description: "代码重构模板",
      variables: ["code"]
    }
  }

  @doc "初始化模板系统，加载内置模板"
  @spec init() :: :ok
  def init do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ets.new(@table, [:named_table, :set, :public])

    Enum.each(@builtin_templates, fn {name, template} ->
      :ets.insert(@table, {name, template})
    end)

    :ok
  end

  @doc "注册自定义模板"
  @spec register(String.t(), String.t(), keyword()) :: :ok
  def register(name, content, opts \\ []) when is_binary(name) and is_binary(content) do
    ensure_table!()

    # 提取 {{variable}} 占位符
    variables = Regex.scan(~r/\{\{(\w+)\}\}/, content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()

    template = %{
      name: name,
      content: content,
      description: Keyword.get(opts, :description, ""),
      variables: variables
    }

    :ets.insert(@table, {name, template})
    :ok
  end

  @doc "获取模板"
  @spec get(String.t()) :: {:ok, template()} | {:error, :not_found}
  def get(name) when is_binary(name) do
    ensure_table!()

    case :ets.lookup(@table, name) do
      [{^name, template}] -> {:ok, template}
      [] -> {:error, :not_found}
    end
  end

  @doc "渲染模板，替换变量"
  @spec render(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def render(name, bindings \\ %{}) when is_binary(name) do
    case get(name) do
      {:ok, template} ->
        rendered = Enum.reduce(bindings, template.content, fn {key, value}, acc ->
          String.replace(acc, "{{#{key}}}", to_string(value))
        end)

        {:ok, rendered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "列出所有可用模板"
  @spec list() :: [template()]
  def list do
    ensure_table!()

    :ets.tab2list(@table)
    |> Enum.map(fn {_name, template} -> template end)
    |> Enum.sort_by(& &1.name)
  end

  @spec cleanup() :: :ok
  def cleanup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  end

  defp ensure_table! do
    if :ets.whereis(@table) == :undefined do
      init()
    end
  end
end
