defmodule Gong.CLI.ChatEventFilterTest do
  use ExUnit.Case, async: true

  alias Gong.CLI.Chat

  test "event_for_command?/2 仅匹配相同 command_id（atom key）" do
    event = %{type: "message.delta", command_id: "cmd-1"}
    assert Chat.event_for_command?(event, "cmd-1")
    refute Chat.event_for_command?(event, "cmd-2")
  end

  test "event_for_command?/2 兼容 string key" do
    event = %{"type" => "lifecycle.completed", "command_id" => "cmd-xyz"}
    assert Chat.event_for_command?(event, "cmd-xyz")
    refute Chat.event_for_command?(event, "cmd-abc")
  end

  test "event_type/1 同时支持 atom/string key" do
    assert Chat.event_type(%{type: "message.start"}) == "message.start"
    assert Chat.event_type(%{"type" => "message.end"}) == "message.end"
    assert Chat.event_type(%{}) == nil
  end
end
