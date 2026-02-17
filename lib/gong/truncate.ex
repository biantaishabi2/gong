defmodule Gong.Truncate do
  @moduledoc deprecated: "请改用 Gong.Utils.Truncate"

  defmodule Result do
    @moduledoc deprecated: "请改用 Gong.Utils.Truncate.Result"

    defstruct content: "",
              truncated: false,
              truncated_by: nil,
              total_lines: 0,
              total_bytes: 0,
              output_lines: 0,
              output_bytes: 0,
              last_line_partial: false,
              first_line_exceeds_limit: false,
              max_lines: nil,
              max_bytes: nil

    @type t :: %__MODULE__{
            content: String.t(),
            truncated: boolean(),
            truncated_by: :lines | :bytes | :chars | nil,
            total_lines: non_neg_integer(),
            total_bytes: non_neg_integer(),
            output_lines: non_neg_integer(),
            output_bytes: non_neg_integer(),
            last_line_partial: boolean(),
            first_line_exceeds_limit: boolean(),
            max_lines: non_neg_integer() | nil,
            max_bytes: non_neg_integer() | nil
          }
  end

  @type strategy :: Gong.Utils.Truncate.strategy()

  @deprecated "请改用 Gong.Utils.Truncate.truncate/3"
  @spec truncate(String.t(), strategy(), keyword()) :: Result.t()
  def truncate(text, strategy \\ :tail, opts \\ []) do
    text
    |> Gong.Utils.Truncate.truncate(strategy, opts)
    |> to_legacy_result()
  end

  @deprecated "请改用 Gong.Utils.Truncate.truncate_line/2"
  @spec truncate_line(String.t(), non_neg_integer()) :: Result.t()
  def truncate_line(text, max_chars) do
    text
    |> Gong.Utils.Truncate.truncate_line(max_chars)
    |> to_legacy_result()
  end

  defp to_legacy_result(%Gong.Utils.Truncate.Result{} = result) do
    result
    |> Map.from_struct()
    |> then(&struct(Result, &1))
  end
end
