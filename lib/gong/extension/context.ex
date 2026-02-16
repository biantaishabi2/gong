defmodule Gong.Extension.Context do
  @moduledoc """
  扩展上下文管理。

  提供动态 model getter，确保 model 值在运行时实时读取，
  而非在初始化时快照。
  """

  @doc """
  构建扩展上下文，model 通过 getter 动态获取。

  返回一个包含 model_getter 函数的上下文 map，
  调用 get_model/1 时始终返回最新值。

  ## 示例

      ctx = Gong.Extension.Context.build(%{model: "gpt-4"})
      Gong.Extension.Context.get_model(ctx) #=> "gpt-4"
      # 如果底层 model 被更新，get_model 返回新值
  """
  @spec build(map()) :: map()
  def build(config) when is_map(config) do
    # 使用 getter 函数代替快照值，确保动态更新
    model_ref = make_ref()
    :persistent_term.put({__MODULE__, model_ref}, Map.get(config, :model, "default"))

    %{
      model_ref: model_ref,
      config: config,
      model_getter: fn -> :persistent_term.get({__MODULE__, model_ref}) end
    }
  end

  @doc """
  获取当前 model 值（动态读取，非快照）。
  """
  @spec get_model(map()) :: String.t()
  def get_model(%{model_getter: getter}) when is_function(getter, 0) do
    getter.()
  end

  @doc """
  更新上下文中的 model 值。
  """
  @spec update_model(map(), String.t()) :: map()
  def update_model(%{model_ref: ref} = ctx, new_model) when is_binary(new_model) do
    :persistent_term.put({__MODULE__, ref}, new_model)
    ctx
  end

  @doc """
  清理上下文持有的资源。
  """
  @spec cleanup(map()) :: :ok
  def cleanup(%{model_ref: ref}) do
    :persistent_term.erase({__MODULE__, ref})
    :ok
  rescue
    _ -> :ok
  end

  def cleanup(_), do: :ok
end
