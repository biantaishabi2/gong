defmodule Gong.Provider do
  @moduledoc """
  Provider behaviour — 多 LLM Provider 统一接口。

  每个 Provider 实现 chat/stream 方法，通过 ProviderRegistry 管理。
  """

  @type message :: map()
  @type tool :: map()
  @type opts :: keyword()

  @callback name() :: String.t()
  @callback chat(messages :: [message()], tools :: [tool()], opts :: opts()) ::
              {:ok, map()} | {:error, term()}
  @callback stream(messages :: [message()], tools :: [tool()], opts :: opts()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback default_model() :: String.t()
  @callback validate_config(config :: map()) :: :ok | {:error, String.t()}

  defmacro __using__(_opts) do
    quote do
      @behaviour Gong.Provider

      @impl true
      def stream(_messages, _tools, _opts), do: {:error, "流式不支持"}

      @impl true
      def validate_config(_config), do: :ok

      defoverridable stream: 3, validate_config: 1
    end
  end
end
