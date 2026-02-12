defmodule GongTest do
  use ExUnit.Case, async: true

  test "模块加载" do
    assert Code.ensure_loaded?(Gong)
  end
end
