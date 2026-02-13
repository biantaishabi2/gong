defmodule Gong.BDD.InstructionRegistries.FollowUp do
  @moduledoc "Follow-up 消息队列 BDD 指令注册"

  def specs(:v1) do
    %{
      inject_follow_up: %{
        name: :inject_follow_up,
        kind: :given,
        args: %{
          message: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      steering_check_follow_up: %{
        name: :steering_check_follow_up,
        kind: :when,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      },
      assert_follow_up_message: %{
        name: :assert_follow_up_message,
        kind: :then,
        args: %{
          contains: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      assert_follow_up_empty: %{
        name: :assert_follow_up_empty,
        kind: :then,
        args: %{},
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: :C
      },
      push_steering_message: %{
        name: :push_steering_message,
        kind: :given,
        args: %{
          message: %{type: :string, required?: true, allowed: nil}
        },
        outputs: %{},
        rules: [],
        boundary: :test_runtime,
        scopes: [:unit, :integration],
        async?: false,
        eventually?: false,
        assert_class: nil
      }
    }
  end

  def specs(:v2), do: %{}
end
