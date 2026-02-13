defmodule Gong.Tape.Entry do
  @moduledoc "Tape 条目结构体"

  @type t :: %__MODULE__{
          id: String.t() | nil,
          anchor: String.t(),
          kind: String.t(),
          content: String.t(),
          timestamp: integer(),
          metadata: map()
        }

  @derive Jason.Encoder
  defstruct [:id, :anchor, :kind, :content, :timestamp, metadata: %{}]

  @spec new(String.t(), String.t(), String.t(), map()) :: t()
  def new(anchor, kind, content, metadata \\ %{}) do
    %__MODULE__{
      id: generate_id(),
      anchor: anchor,
      kind: kind,
      content: content,
      timestamp: System.os_time(:millisecond),
      metadata: metadata
    }
  end

  @spec from_json(String.t()) :: {:ok, t()} | :error
  def from_json(line) do
    case Jason.decode(line) do
      {:ok, %{"id" => id, "kind" => kind, "content" => content, "timestamp" => ts} = map}
      when is_binary(id) and is_binary(kind) and is_binary(content) and is_integer(ts) ->
        {:ok,
         %__MODULE__{
           id: id,
           anchor: map["anchor"],
           kind: kind,
           content: content,
           timestamp: ts,
           metadata: map["metadata"] || %{}
         }}

      _ ->
        :error
    end
  end

  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = entry) do
    Jason.encode!(Map.from_struct(entry))
  end

  defp generate_id do
    "entry_" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))
  end
end
