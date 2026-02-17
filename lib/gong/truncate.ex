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
  end

  @type strategy :: Gong.Utils.Truncate.strategy()

  @deprecated "请改用 Gong.Utils.Truncate.truncate/3"
  @spec truncate(String.t(), strategy(), keyword()) :: Gong.Utils.Truncate.Result.t()
  defdelegate truncate(text, strategy \\ :tail, opts \\ []), to: Gong.Utils.Truncate

  @deprecated "请改用 Gong.Utils.Truncate.truncate_line/2"
  @spec truncate_line(String.t(), non_neg_integer()) :: Gong.Utils.Truncate.Result.t()
  defdelegate truncate_line(text, max_chars), to: Gong.Utils.Truncate
end
