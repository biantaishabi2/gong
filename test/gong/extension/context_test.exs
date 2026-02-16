defmodule Gong.Extension.ContextTest do
  use ExUnit.Case, async: false

  alias Gong.Extension.Context

  # pi-mono bugfix 回归: 扩展上下文 model 动态更新
  # Pi#26

  describe "build/update_model/get_model" do
    test "构建后可获取 model" do
      ctx = Context.build(%{model: "gpt-4"})
      assert Context.get_model(ctx) == "gpt-4"
      Context.cleanup(ctx)
    end

    test "动态更新 model" do
      ctx = Context.build(%{model: "gpt-4"})
      updated = Context.update_model(ctx, "claude-3")
      assert Context.get_model(updated) == "claude-3"
      Context.cleanup(updated)
    end
  end
end
