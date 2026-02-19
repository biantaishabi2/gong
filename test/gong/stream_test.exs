defmodule Gong.StreamTest do
  use ExUnit.Case, async: true

  alias Gong.Stream

  test "chunks_to_events 在 abort reason 为 map 时不会崩溃" do
    events = Stream.chunks_to_events([{:chunk, "hello"}, {:abort, %{a: 1}}])

    assert Enum.map(events, & &1.type) == [:text_start, :text_delta, :error, :text_end]
    assert Enum.at(events, 2).content == "%{a: 1}"
  end

  test "chunks_to_events 在首事件 abort 且 reason 非字符串时不会崩溃" do
    events = Stream.chunks_to_events([{:abort, [:bad, :reason]}])

    assert Enum.map(events, & &1.type) == [:error]
    assert Enum.at(events, 0).content == "[:bad, :reason]"
  end
end
