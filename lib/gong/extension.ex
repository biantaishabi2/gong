defmodule Gong.Extension do
  @moduledoc """
  Extension behaviour 定义。

  扩展可以提供自定义工具、命令、Hook 回调。
  """

  @callback name() :: String.t()
  @callback init(opts :: keyword()) :: {:ok, state :: term()} | {:error, term()}
  @callback tools() :: [module()]
  @callback commands() :: [map()]
  @callback hooks() :: [module()]
  @callback cleanup(state :: term()) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour Gong.Extension

      # 默认实现
      def init(_opts), do: {:ok, %{}}
      def tools, do: []
      def commands, do: []
      def hooks, do: []
      def cleanup(_state), do: :ok

      defoverridable [init: 1, tools: 0, commands: 0, hooks: 0, cleanup: 1]
    end
  end
end
