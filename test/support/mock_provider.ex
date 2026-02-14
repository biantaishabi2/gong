defmodule Gong.Test.MockProvider do
  @moduledoc "测试用 Mock Provider"
  use Gong.Provider

  @impl true
  def name, do: "mock"

  @impl true
  def chat(_messages, _tools, _opts), do: {:ok, %{content: "mock response"}}

  @impl true
  def default_model, do: "mock-model"
end

defmodule Gong.Test.MockProviderWithValidation do
  @moduledoc "测试用 Mock Provider（带配置校验）"
  use Gong.Provider

  @impl true
  def name, do: "mock_validated"

  @impl true
  def chat(_messages, _tools, _opts), do: {:ok, %{content: "mock"}}

  @impl true
  def default_model, do: "mock-model"

  @impl true
  def validate_config(%{invalid: true}), do: {:error, "invalid config"}
  def validate_config(_), do: :ok
end
