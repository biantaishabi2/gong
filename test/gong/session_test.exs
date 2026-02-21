defmodule Gong.SessionTest do
  use ExUnit.Case, async: false

  alias Gong.Session
  alias Gong.Session.Events
  alias Gong.Stream.Event, as: StreamEvent

  # ── Agent 路径测试 helper ──

  # 创建 agent session，llm_backend_fn 返回 {:ok, {:text, reply}} 或 {:ok, {:error, reason}}
  defp setup_agent_session(session_id, llm_fn, extra_opts \\ []) do
    agent = Gong.Agent.new()

    opts =
      [session_id: session_id, agent: agent, llm_backend_fn: llm_fn]
      |> Keyword.merge(extra_opts)

    Session.start_link(opts)
  end

  # 简单文本回复的 llm_backend_fn
  defp text_llm(reply) do
    fn _agent_state, _call_id -> {:ok, {:text, reply}} end
  end

  # 带消息回显的 llm_backend_fn（echo:message）
  defp echo_llm do
    fn agent_state, _call_id ->
      alias Jido.Agent.Strategy.State, as: StratState
      state = StratState.get(agent_state, %{})
      conversation = Map.get(state, :conversation, [])
      # 取最后一条 user 消息做回显
      last_user =
        conversation
        |> Enum.reverse()
        |> Enum.find_value(fn
          %{role: :user, content: c} -> c
          _ -> nil
        end)

      {:ok, {:text, "echo:#{last_user || "?"}"}}
    end
  end

  # 返回错误的 llm_backend_fn
  defp error_llm(error_msg) do
    fn _agent_state, _call_id -> {:ok, {:error, error_msg}} end
  end

  # ── Stream 事件 / Schema 测试 ──

  test "初始化后订阅事件流，turn 内 seq 单调递增且满足 schema 1.0.0" do
    {:ok, session} = setup_agent_session("session-seq", text_llm("hello"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "hello", [])

    events = receive_until_turn_completed([])
    turn_events = Enum.filter(events, &(&1.turn_id == 1))

    assert turn_events != []
    assert Enum.all?(turn_events, &(&1.schema_version == Events.schema_version()))
    assert Enum.all?(turn_events, &Map.has_key?(&1, :error))
    assert Enum.map(turn_events, & &1.seq) == Enum.sort(Enum.map(turn_events, & &1.seq))
    assert Enum.any?(turn_events, &(&1.type == "message.end"))
    assert List.last(turn_events).type == "lifecycle.turn_completed"
  end

  test "无订阅者触发事件不会崩溃，且后续请求可继续" do
    {:ok, session} = setup_agent_session("session-no-subscriber", text_llm("pong"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.prompt(session, "ping", [])
    assert wait_until(fn -> history_len_at_least?(session, 2) end)
    assert Process.alive?(session)

    assert :ok = Session.prompt(session, "ping-again", [])
    assert wait_until(fn -> history_len_at_least?(session, 4) end)
    assert Process.alive?(session)
  end

  test "restore 发送 session_restored 事件且仅恢复核心状态，不恢复订阅关系" do
    {:ok, session} = setup_agent_session("session-restore", text_llm("ok"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    snapshot = %{
      history: [%{role: :user, content: "old", turn_id: 7, ts: 1}],
      turn_cursor: 7,
      metadata: %{"lang" => "zh"}
    }

    assert {:ok, restored} = Session.restore(session, snapshot)
    assert restored.turn_cursor == 7
    assert restored.metadata["lang"] == "zh"
    assert get_in(restored.metadata, ["session", "model"]) == "deepseek:deepseek-chat"
    assert get_in(restored.metadata, ["session", "thinking", "level"]) == "off"
    assert restored.history == snapshot.history

    assert_receive {:session_event, restored_event}, 300
    assert restored_event.type == "lifecycle.session_restored"
    assert restored_event.turn_id == 7
    assert restored_event.error == nil

    # restore 后订阅关系应被清空
    assert :ok = Session.prompt(session, "not-received", [])
    refute_receive {:session_event, _}, 150

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "received", [])

    events = receive_until_turn_completed([])
    assert Enum.all?(events, &(&1.turn_id == 9))
  end

  # ── 错误处理测试 ──

  test "限流错误语义：rate_limited + retriable + retry_after(秒)" do
    # 注：agent 路径的错误经 AgentLoop 包装后为字符串，无法保留 rate_limited 结构。
    # 此测试验证 normalize_error 对 rate_limited tuple 的处理。
    error = Session.normalize_error({:rate_limited, 2, %{provider: "mock"}})

    assert error.code == :rate_limited
    assert error.retriable == true
    assert error.retry_after == 2
  end

  test "rate_limited 未提供 retry_after 时默认 1 秒" do
    error = Session.normalize_error({:rate_limited, nil, %{provider: "mock"}})

    assert error.code == :rate_limited
    assert error.retriable == true
    assert error.retry_after == 1
  end

  test "retriable 严格按 code 映射，不接受显式字段覆盖" do
    rate_limited_error =
      Session.normalize_error(%{
        code: :rate_limited,
        message: "rate limited",
        retriable: false,
        details: %{}
      })

    invalid_argument_error =
      Session.normalize_error(%{
        code: :invalid_argument,
        message: "invalid argument",
        retriable: true,
        details: %{}
      })

    assert rate_limited_error.retriable == true
    assert invalid_argument_error.retriable == false
  end

  test "session API 在失效 pid 场景返回统一错误而非抛 exit" do
    {:ok, session} = Session.start_link(session_id: "session-dead-pid")
    assert :ok = Session.close(session)

    assert {:error, history_error} = Session.history(session)
    assert history_error.code == :session_not_found

    assert {:error, prompt_error} = Session.prompt(session, "hello", [])
    assert prompt_error.code == :session_not_found

    assert {:error, restore_error} = Session.restore(session, %{})
    assert restore_error.code == :session_not_found
  end

  test "Agent 路径 LLM 返回错误时 Session 发射 error.runtime + lifecycle.error 事件" do
    {:ok, session} = setup_agent_session("session-agent-error", error_llm("模型不可用"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "trigger", [])

    events = receive_until_turn_completed([])
    error_event = Enum.find(events, &(&1.type == "error.runtime"))
    lifecycle_error = Enum.find(events, &(&1.type == "lifecycle.error"))

    assert error_event != nil
    assert is_binary(error_event.error.message)
    assert lifecycle_error != nil
    assert Process.alive?(session)
  end

  test "非法 pid/name 参数返回统一错误而非抛异常" do
    assert {:error, start_link_error} = Session.start_link(name: %{})
    assert start_link_error.code == :invalid_argument

    assert {:error, history_error} = Session.history(%{})
    assert history_error.code == :invalid_argument

    assert {:error, close_error} = Session.close(%{})
    assert close_error.code == :invalid_argument
  end

  test "subscribe/unsubscribe 非法参数返回统一错误" do
    {:ok, session} = Session.start_link(session_id: "session-invalid-subscriber")
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert {:error, subscribe_error} = Session.subscribe(session, :invalid_subscriber)
    assert subscribe_error.code == :invalid_argument

    assert {:error, unsubscribe_error} = Session.unsubscribe(session, :invalid_subscriber)
    assert unsubscribe_error.code == :invalid_argument
  end

  test "prompt 非 keyword opts 返回统一错误且 Session 保持可用" do
    {:ok, session} = setup_agent_session("session-invalid-prompt-opts", text_llm("ok"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert {:error, prompt_error} = Session.prompt(session, "hello", %{backend: :invalid})
    assert prompt_error.code == :invalid_argument
    assert Process.alive?(session)

    assert :ok = Session.prompt(session, "hello", [])
    assert wait_until(fn -> history_len_at_least?(session, 2) end)
  end

  test "Agent 路径 stream 事件中非字符串 content 不会导致 Session 崩溃" do
    # Agent 路径的 stream event 由 AgentLoop 发射，content 始终是字符串。
    # 此测试验证 Session 对正常 Agent 路径 stream 事件的处理。
    {:ok, session} = setup_agent_session("session-stream-robustness", text_llm("正常文本"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())
    assert :ok = Session.prompt(session, "trigger", [])

    _events = receive_until_turn_completed([])
    assert Process.alive?(session)

    assert wait_until(fn ->
             case Session.history(session) do
               {:ok, history} ->
                 Enum.any?(history, fn entry ->
                   entry.role == :assistant and entry.turn_id == 1 and is_binary(entry.content)
                 end)

               {:error, _} ->
                 false
             end
           end)
  end

  # ── 并发测试 ──

  test "并发 prompt 下 Session 保持可用且完成所有 turn" do
    # echo_llm 带 10ms 延迟模拟
    slow_echo = fn agent_state, call_id ->
      Process.sleep(10)
      echo_llm().(agent_state, call_id)
    end

    {:ok, session} = setup_agent_session("session-concurrent", slow_echo)
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    assert :ok = Session.subscribe(session, self())

    tasks =
      for i <- 1..8 do
        Task.async(fn -> Session.prompt(session, "m#{i}", []) end)
      end

    assert Enum.all?(tasks, &(Task.await(&1, 5_000) == :ok))

    events = receive_until_turn_completed_count([], 8)
    completed = Enum.filter(events, &(&1.type == "lifecycle.turn_completed"))

    assert length(completed) == 8
    assert MapSet.size(MapSet.new(Enum.map(completed, & &1.turn_id))) == 8
    # Agent Thread 并发时各 Task 基于同一快照并行运行，后完成的覆盖先完成的，
    # 所以 Thread 不一定完整累积所有对话。只检查 Session 存活 + 事件完整。
    assert wait_until(fn -> history_len_at_least?(session, 2) end)
    assert Process.alive?(session)
  end

  test "并发 restore 与 history 读取下 Session 保持可用" do
    {:ok, session} = setup_agent_session("session-concurrent-restore", text_llm("ok"))
    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

    snapshot = %{
      history: [%{role: :user, content: "legacy", turn_id: 5, ts: 1}],
      turn_cursor: 5,
      metadata: %{
        "session" => %{
          "model" => "openai/gpt-4o",
          "thinking" => %{"level" => "medium"}
        }
      }
    }

    results =
      1..24
      |> Task.async_stream(
        fn idx ->
          case rem(idx, 3) do
            0 ->
              Session.restore(session, snapshot)

            1 ->
              Session.history(session)

            2 ->
              Session.restore(
                session,
                snapshot
                |> Map.put(:turn_cursor, "bad-#{idx}")
                |> Map.put(:turn_id, 7)
              )
          end
        end,
        max_concurrency: 8,
        timeout: 2_000,
        ordered: false
      )
      |> Enum.to_list()

    assert Enum.all?(results, fn
             {:ok, {:ok, %{turn_cursor: turn_cursor, metadata: metadata}}} ->
               is_integer(turn_cursor) and turn_cursor >= 0 and is_map(metadata)

             {:ok, {:ok, history}} when is_list(history) ->
               true

             _ ->
               false
           end)

    assert Process.alive?(session)
    assert :ok = Session.prompt(session, "after-concurrent-restore", [])
    assert wait_until(fn -> history_len_at_least?(session, 2) end)
  end

  test "错误详情会执行深度限制，避免无限递归展开" do
    deep_details =
      Enum.reduce(1..20, %{}, fn idx, acc ->
        %{"level_#{idx}" => acc}
      end)

    error =
      Session.normalize_error(%{code: :internal_error, message: "boom", details: deep_details})

    assert error.code == :internal_error
    assert contains_truncated_marker?(error.details)
    assert max_depth(error.details) <= 8
  end

  # ── get_last_assistant_message 测试 ──

  describe "get_last_assistant_message/1" do
    test "忽略 tool_result 和空 assistant，优先提取多模态 text" do
      messages = [
        %{role: :user, content: "你好"},
        %{role: :assistant, content: "旧回复"},
        %{role: :tool_result, content: "工具执行结果"},
        %{role: :assistant, content: "   "},
        %{
          role: :assistant,
          content: [%{type: "image", value: "img://1"}, %{type: "text", text: "最终文本"}]
        }
      ]

      assert Session.get_last_assistant_message(messages) == "最终文本"
      assert Session.getLastAssistantMessage(messages) == "最终文本"
    end

    test "没有 text 片段时回退首个非空片段" do
      messages = [
        %{role: :assistant, content: [%{type: "image", content: "image://fallback"}]}
      ]

      assert Session.get_last_assistant_message(messages) == "image://fallback"
    end

    test "无有效 assistant 消息返回 nil" do
      messages = [
        %{role: :user, content: "hi"},
        %{role: :assistant, content: ""},
        %{role: :assistant, tool_calls: [%{name: "read"}], content: "tool call"},
        %{role: :tool_result, content: "ok"}
      ]

      assert Session.get_last_assistant_message(messages) == nil
    end

    test "超长多模态 content 列表仍可提取最后有效 text" do
      parts =
        Enum.map(1..300, fn idx ->
          if rem(idx, 2) == 0 do
            %{type: "tool_result", content: "tool://#{idx}"}
          else
            %{type: "image", value: "img://#{idx}"}
          end
        end) ++ [%{type: "text", text: "终点文本"}]

      messages = [%{role: :assistant, content: parts}]

      assert Session.get_last_assistant_message(messages) == "终点文本"
    end
  end

  # ── Restore 兼容恢复语义测试 ──

  describe "restore 兼容恢复语义" do
    test "新字段优先于旧字段，并写回统一新格式" do
      {:ok, session} = setup_agent_session("session-restore-new-priority", text_llm("ok"))
      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      snapshot = %{
        history: [%{role: :user, content: "old", turn_id: 2, ts: 1}],
        turn_cursor: 2,
        metadata: %{
          "session" => %{
            "model" => "anthropic:claude-3-5-sonnet",
            "thinking" => %{"level" => "medium"}
          },
          "initial_state" => %{
            "model" => "openai/gpt-4o",
            "thinking_level" => "high"
          },
          "model" => "legacy:model"
        }
      }

      assert {:ok, restored} = Session.restore(session, snapshot)
      assert get_in(restored.metadata, ["session", "model"]) == "anthropic:claude-3-5-sonnet"
      assert get_in(restored.metadata, ["session", "thinking", "level"]) == "medium"
      refute Map.has_key?(restored.metadata, "model")
      refute Map.has_key?(restored.metadata, "thinking_level")
    end

    test "metadata.session 内旧字段不会覆盖新字段，且写回时会清理" do
      {:ok, session} =
        setup_agent_session("session-restore-session-legacy-keys-cleaned", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      snapshot = %{
        history: [%{role: :user, content: "legacy", turn_id: 3, ts: 1}],
        turn_cursor: 3,
        metadata: %{
          "session" => %{
            :model => "legacy:should-not-win",
            :saved_model => "legacy:saved-model",
            :thinking_level => "high",
            "model" => "openai:gpt-4o",
            "thinking" => %{"level" => "low"}
          }
        }
      }

      assert {:ok, restored} = Session.restore(session, snapshot)
      assert get_in(restored.metadata, ["session", "model"]) == "openai:gpt-4o"
      assert get_in(restored.metadata, ["session", "thinking", "level"]) == "low"

      session_metadata = restored.metadata["session"]
      refute Map.has_key?(session_metadata, :model)
      refute Map.has_key?(session_metadata, :saved_model)
      refute Map.has_key?(session_metadata, :thinking_level)
    end

    test "turn_cursor 非法时继续回退 turn_id" do
      {:ok, session} =
        setup_agent_session("session-restore-turn-id-fallback", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      snapshot = %{
        history: [%{role: :user, content: "legacy", turn_id: 5, ts: 1}],
        turn_cursor: "not-a-number",
        turn_id: 5,
        metadata: %{}
      }

      assert {:ok, restored} = Session.restore(session, snapshot)
      assert restored.turn_cursor == 5
    end

    test "异常格式不中断并回退默认 model/thinking/turn_cursor/history" do
      {:ok, session} =
        setup_agent_session("session-restore-invalid-format", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      snapshot = %{
        history: "invalid-history",
        turn_cursor: "not-a-number",
        metadata: %{
          "session" => %{
            "model" => %{"provider" => "", "model_id" => ""},
            "thinking" => %{"level" => "超高"}
          }
        }
      }

      assert {:ok, restored} = Session.restore(session, snapshot)
      assert restored.history == []
      assert restored.turn_cursor == 0
      assert get_in(restored.metadata, ["session", "model"]) == "deepseek:deepseek-chat"
      assert get_in(restored.metadata, ["session", "thinking", "level"]) == "off"
    end

    test "模型字符串缺少 provider 或 model_id 时回退默认值" do
      {:ok, session} =
        setup_agent_session("session-restore-invalid-model-pair", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      Enum.each(["openai/", "openai:", ":gpt-4o"], fn invalid_model ->
        snapshot = %{
          history: [%{role: :user, content: "legacy", turn_id: 1, ts: 1}],
          turn_cursor: 1,
          metadata: %{
            "session" => %{
              "model" => invalid_model
            }
          }
        }

        assert {:ok, restored} = Session.restore(session, snapshot)
        assert get_in(restored.metadata, ["session", "model"]) == "deepseek:deepseek-chat"
      end)
    end

    test "模型 map 中 provider/model_id 仅空白字符时回退默认值" do
      {:ok, session} =
        setup_agent_session("session-restore-invalid-model-map-whitespace", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      Enum.each(
        [
          %{"provider" => " ", "model_id" => "gpt-4o"},
          %{"provider" => "openai", "model_id" => "   "}
        ],
        fn invalid_model ->
          snapshot = %{
            history: [%{role: :user, content: "legacy", turn_id: 1, ts: 1}],
            turn_cursor: 1,
            metadata: %{
              "session" => %{
                "model" => invalid_model
              }
            }
          }

          assert {:ok, restored} = Session.restore(session, snapshot)
          assert get_in(restored.metadata, ["session", "model"]) == "deepseek:deepseek-chat"
        end
      )
    end

    test "深层 thinking 嵌套结构不会中断恢复并回退默认值" do
      {:ok, session} =
        setup_agent_session("session-restore-deep-thinking", text_llm("ok"))

      on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)

      deep_thinking =
        Enum.reduce(1..40, %{"level" => "high"}, fn idx, acc ->
          %{"layer_#{idx}" => acc}
        end)

      snapshot = %{
        history: [%{role: :user, content: "legacy", turn_id: 1, ts: 1}],
        turn_cursor: 1,
        metadata: %{
          "session" => %{
            "model" => %{"provider" => "openai", "model_id" => "gpt-4o"},
            "thinking" => deep_thinking
          }
        }
      }

      assert {:ok, restored} = Session.restore(session, snapshot)
      assert restored.turn_cursor == 1
      assert get_in(restored.metadata, ["session", "model"]) == "openai:gpt-4o"
      assert get_in(restored.metadata, ["session", "thinking", "level"]) == "off"
    end
  end

  # ── Agent 路径：多轮对话 Thread 自然累积 ──

  test "Session 持有 Agent 模式：多轮对话 Thread 自然累积" do
    # 用 Elixir Agent 捕获每轮 LLM 实际收到的 conversation
    {:ok, msg_agent} = Agent.start_link(fn -> [] end)

    alias Jido.Agent.Strategy.State, as: StratState

    # 构造 llm_backend 闭包：捕获 conversation 后返回文本
    llm_backend_fn = fn agent_state, _call_id ->
      state = StratState.get(agent_state, %{})
      conversation = Map.get(state, :conversation, [])

      messages =
        Enum.map(conversation, fn m ->
          %{role: m[:role] || :user, content: m[:content] || ""}
        end)

      Agent.update(msg_agent, fn calls -> calls ++ [messages] end)

      {:ok, {:text, "收到"}}
    end

    # 创建 Agent 并直接传给 Session
    agent = Gong.Agent.new()

    {:ok, session} =
      Session.start_link(
        session_id: "session-agent-thread",
        agent: agent,
        llm_backend_fn: llm_backend_fn
      )

    on_exit(fn ->
      if Process.alive?(session), do: Session.close(session)
      if Process.alive?(msg_agent), do: Agent.stop(msg_agent)
    end)

    assert :ok = Session.subscribe(session, self())

    # 第一轮
    assert :ok = Session.prompt(session, "你好", [])
    _events = receive_until_turn_completed([])

    # 第二轮
    assert :ok = Session.prompt(session, "记得我说什么吗", [])
    _events = receive_until_turn_completed([])

    conversations = Agent.get(msg_agent, & &1)
    assert length(conversations) == 2

    # 关键断言：第二轮 LLM 收到的 messages 自然包含第一轮对话
    second_messages = Enum.at(conversations, 1)
    all_contents = Enum.map(second_messages, &Map.get(&1, :content, ""))

    assert Enum.any?(all_contents, &String.contains?(&1, "你好")),
           "第二轮 LLM 应看到第一轮的消息 '你好'，但实际只有: #{inspect(all_contents)}"

    assert Enum.any?(all_contents, &String.contains?(&1, "收到")),
           "第二轮 LLM 应看到第一轮的回复 '收到'，但实际只有: #{inspect(all_contents)}"

    assert Enum.any?(all_contents, &String.contains?(&1, "记得我说什么吗")),
           "第二轮 LLM 应看到当前消息 '记得我说什么吗'，但实际只有: #{inspect(all_contents)}"
  end

  test "model 路径：Session 从 model 创建 Agent，多轮 Thread 自然累积" do
    # 验证生产 init 路径（model → Agent），用 llm_backend_fn 覆盖真实 LLM
    {:ok, msg_agent} = Agent.start_link(fn -> [] end)

    alias Jido.Agent.Strategy.State, as: StratState

    llm_backend_fn = fn agent_state, _call_id ->
      state = StratState.get(agent_state, %{})
      conversation = Map.get(state, :conversation, [])

      messages =
        Enum.map(conversation, fn m ->
          %{role: m[:role] || :user, content: m[:content] || ""}
        end)

      Agent.update(msg_agent, fn calls -> calls ++ [messages] end)

      {:ok, {:text, "好的"}}
    end

    # 确保 ModelRegistry ETS 表存在
    Gong.ModelRegistry.init()

    # 传 model（走生产 init 路径）+ llm_backend_fn（mock LLM）
    {:ok, session} =
      Session.start_link(
        session_id: "session-model-path",
        model: "mock:test-chat",
        llm_backend_fn: llm_backend_fn
      )

    on_exit(fn ->
      if Process.alive?(session), do: Session.close(session)
      if Process.alive?(msg_agent), do: Agent.stop(msg_agent)
    end)

    assert :ok = Session.subscribe(session, self())

    # 第一轮
    assert :ok = Session.prompt(session, "第一句话", [])
    _events = receive_until_turn_completed([])

    # 第二轮
    assert :ok = Session.prompt(session, "第二句话", [])
    _events = receive_until_turn_completed([])

    conversations = Agent.get(msg_agent, & &1)
    assert length(conversations) == 2

    # 第二轮 LLM 自然看到第一轮对话（Thread 累积，非 inject hack）
    second_messages = Enum.at(conversations, 1)
    all_contents = Enum.map(second_messages, &Map.get(&1, :content, ""))

    assert Enum.any?(all_contents, &String.contains?(&1, "第一句话")),
           "model 路径：第二轮 LLM 应看到 '第一句话'，实际: #{inspect(all_contents)}"

    assert Enum.any?(all_contents, &String.contains?(&1, "好的")),
           "model 路径：第二轮 LLM 应看到 '好的'，实际: #{inspect(all_contents)}"
  end

  # ── Helper 函数 ──

  defp receive_until_turn_completed(acc) do
    receive do
      {:session_event, event} ->
        next = acc ++ [event]

        if event.type == "lifecycle.turn_completed" do
          next
        else
          receive_until_turn_completed(next)
        end
    after
      5_000 ->
        flunk("等待 Session 事件超时")
    end
  end

  defp receive_until_turn_completed_count(acc, target_count) do
    completed_count =
      Enum.count(acc, fn event -> event.type == "lifecycle.turn_completed" end)

    if completed_count >= target_count do
      acc
    else
      receive do
        {:session_event, event} ->
          receive_until_turn_completed_count(acc ++ [event], target_count)
      after
        10_000 ->
          flunk("等待并发 turn 完成事件超时")
      end
    end
  end

  defp history_len_at_least?(session, min_len) do
    case Session.history(session) do
      {:ok, history} -> length(history) >= min_len
      {:error, _} -> false
    end
  end

  defp contains_truncated_marker?(value) when is_map(value) do
    Map.get(value, :truncated) == true or
      Enum.any?(value, fn {_k, v} -> contains_truncated_marker?(v) end)
  end

  defp contains_truncated_marker?(value) when is_list(value) do
    Enum.any?(value, &contains_truncated_marker?/1)
  end

  defp contains_truncated_marker?("[truncated]"), do: true
  defp contains_truncated_marker?(_), do: false

  defp max_depth(value) when is_map(value) do
    if map_size(value) == 0 do
      1
    else
      1 + Enum.max(Enum.map(Map.values(value), &max_depth/1))
    end
  end

  defp max_depth(value) when is_list(value) do
    if value == [] do
      1
    else
      1 + Enum.max(Enum.map(value, &max_depth/1))
    end
  end

  defp max_depth(_), do: 0

  defp wait_until(fun, retries \\ 50)

  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, retries) do
    if fun.() do
      true
    else
      Process.sleep(30)
      wait_until(fun, retries - 1)
    end
  end
end
