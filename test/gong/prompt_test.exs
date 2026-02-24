defmodule Gong.PromptTest do
  use ExUnit.Case, async: true

  alias Gong.Prompt

  test "full_system_prompt 注入当前模型与可用模型列表" do
    prompt =
      Prompt.full_system_prompt(
        workspace: "/tmp/project",
        current_model: "kimi",
        available_models: ["kimi(kimi:k2p5)", "minimax(minimax:MiniMax-M2.5)"]
      )

    assert prompt =~ "当前模型：kimi"
    assert prompt =~ "可用模型：kimi(kimi:k2p5), minimax(minimax:MiniMax-M2.5)"
    assert prompt =~ "当前工作目录：/tmp/project"
  end
end
