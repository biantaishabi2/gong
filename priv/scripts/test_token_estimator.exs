# 实测 TokenEstimator 精度：对比估算值 vs LLM API 返回的 input_tokens
#
# 用法: mix run priv/scripts/test_token_estimator.exs

alias Gong.Compaction.TokenEstimator

model = "deepseek:deepseek-chat"

defmodule TokenTest do
  def run_test(name, messages, model) do
    estimate = Gong.Compaction.TokenEstimator.estimate_messages(messages)

    opts = [receive_timeout: 30_000]
    case ReqLLM.generate_text(model, messages, opts) do
      {:ok, response} ->
        usage = extract_usage(response)
        actual = usage.input_tokens
        deviation = if actual > 0, do: abs(estimate - actual) / actual * 100, else: 0
        direction = if estimate > actual, do: "偏高", else: "偏低"

        IO.puts("┌─ #{name}")
        IO.puts("│  消息数: #{length(messages)}")
        IO.puts("│  估算值: #{estimate}")
        IO.puts("│  实际值: #{actual}")
        IO.puts("│  偏差率: #{Float.round(deviation, 1)}% (#{direction})")
        IO.puts("│  #{if deviation < 20, do: "✅ PASS", else: "❌ FAIL (>20%)"}")
        IO.puts("└─")
        IO.puts("")

        %{name: name, estimate: estimate, actual: actual, deviation: deviation, direction: direction}

      {:error, reason} ->
        IO.puts("┌─ #{name}")
        IO.puts("│  ❌ API 调用失败: #{inspect(reason)}")
        IO.puts("└─")
        nil
    end
  end

  defp extract_usage(response) do
    usage_data =
      cond do
        is_map(response) -> Map.get(response, :usage, %{})
        true -> %{}
      end

    input =
      Map.get(usage_data, :input_tokens,
        Map.get(usage_data, "input_tokens",
          Map.get(usage_data, :prompt_tokens,
            Map.get(usage_data, "prompt_tokens", 0)))) || 0

    %{input_tokens: input}
  end
end

IO.puts("=" |> String.duplicate(60))
IO.puts("TokenEstimator 实测精度验证")
IO.puts("模型: #{model}")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# 场景 1: 短对话
short_msgs = [
  %{role: "system", content: "你是一个有帮助的助手。"},
  %{role: "user", content: "你好，请帮我解释一下 Elixir 的 GenServer 是什么？"},
  %{role: "assistant", content: "GenServer 是 Elixir 中用于实现服务器进程的行为模块。它封装了状态管理、消息处理和错误恢复的通用模式。"},
  %{role: "user", content: "能给个简单的例子吗？"}
]

# 场景 2: 多轮中英混合长对话
long_msgs = [
  %{role: "system", content: "You are a senior Elixir developer. Answer in Chinese with code examples."},
  %{role: "user", content: "请解释 Phoenix LiveView 的生命周期"},
  %{role: "assistant", content: "Phoenix LiveView 的生命周期包含以下关键阶段：\n\n1. mount/3 — 初始化阶段\n2. handle_params/3 — URL 参数变化时触发\n3. render/1 — 渲染模板\n4. handle_event/3 — 处理用户交互\n5. handle_info/2 — 处理进程间消息\n\n```elixir\ndefmodule MyAppWeb.CounterLive do\n  use MyAppWeb, :live_view\n\n  def mount(_params, _session, socket) do\n    {:ok, assign(socket, count: 0)}\n  end\n\n  def handle_event(\"increment\", _params, socket) do\n    {:noreply, update(socket, :count, &(&1 + 1))}\n  end\nend\n```"},
  %{role: "user", content: "handle_info 和 handle_event 有什么区别？"},
  %{role: "assistant", content: "主要区别在于消息来源：\n\n- handle_event/3 处理来自浏览器端的用户交互\n- handle_info/2 处理来自服务端的消息（PubSub、定时器等）\n\n```elixir\ndef handle_event(\"delete\", %{\"id\" => id}, socket) do\n  Items.delete(id)\n  {:noreply, stream_delete(socket, :items, %{id: id})}\nend\n\ndef handle_info({:item_created, item}, socket) do\n  {:noreply, stream_insert(socket, :items, item)}\nend\n```"},
  %{role: "user", content: "stream 和 assign 的性能差异大吗？"},
  %{role: "assistant", content: "在大列表场景下差异显著：\n\nassign: 全量存储在 socket，重新渲染整个列表\nstream: 只存 DOM 指令，只传增量变更\n\n推荐用 stream 的场景：\n1. 聊天消息列表\n2. 实时数据 feed\n3. 分页列表（无限滚动）\n4. 任何超过 100 项的动态列表"},
  %{role: "user", content: "好的，最后一个问题：LiveView 的测试怎么写？"}
]

# 场景 3: 模拟工具输出（用 assistant 消息包含代码内容）
tool_output_msgs = [
  %{role: "system", content: "你是一个编程助手。"},
  %{role: "user", content: "帮我看看压缩模块的实现"},
  %{role: "assistant", content: "文件内容如下：\n\n```elixir\ndefmodule Gong.Compaction do\n  @moduledoc \"上下文压缩模块。\"\n  alias Gong.Compaction.TokenEstimator\n  alias Gong.Utils.Truncate\n\n  @default_window_size 20\n  @default_max_tokens 100_000\n  @default_reserve_tokens 16_384\n\n  def compact(messages, opts \\\\ []) do\n    window_size = Keyword.get(opts, :window_size, @default_window_size)\n    max_tokens = resolve_max_tokens(opts)\n    summarize_fn = Keyword.get(opts, :summarize_fn, &default_summarize/1)\n    total = TokenEstimator.estimate_messages(messages)\n    if total <= max_tokens do\n      {messages, nil}\n    else\n      {old, recent} = split_with_system_preserved(messages, window_size)\n      if old == [] do\n        {messages, nil}\n      else\n        case summarize_fn.(old) do\n          {:ok, summary} ->\n            summary_msg = %{role: \"system\", content: \"[会话摘要]\"}\n            {[summary_msg | recent], summary}\n          {:error, _reason} ->\n            {truncate_tool_outputs(recent, max_tokens), nil}\n        end\n      end\n    end\n  end\n\n  def split_with_system_preserved(messages, window_size) do\n    {system_msgs, non_system} = Enum.split_with(messages, fn msg ->\n      get_role(msg) in [\"system\", \"branch_summary\"]\n    end)\n    if length(non_system) <= window_size do\n      {[], system_msgs ++ non_system}\n    else\n      split_at = length(non_system) - window_size\n      safe_split = find_safe_boundary(non_system, split_at)\n      {old, recent_non_system} = Enum.split(non_system, safe_split)\n      {old, system_msgs ++ recent_non_system}\n    end\n  end\nend\n```\n\n核心逻辑：固定保留最近 20 条非系统消息，超阈值时旧消息交给 LLM 摘要。"},
  %{role: "user", content: "截断策略是怎么工作的？"}
]

# 场景 4: JSON 密集内容
json_msgs = [
  %{role: "system", content: "You are a config review assistant."},
  %{role: "user", content: "Review this config"},
  %{role: "assistant", content: "Here's the config analysis:\n\n```json\n{\n  \"database\": {\n    \"host\": \"localhost\",\n    \"port\": 5432,\n    \"name\": \"gong_dev\",\n    \"pool_size\": 10,\n    \"ssl\": false,\n    \"timeout\": 15000\n  },\n  \"llm\": {\n    \"providers\": {\n      \"deepseek\": {\n        \"api_key\": \"${DEEPSEEK_API_KEY}\",\n        \"base_url\": \"https://api.deepseek.com/v1\",\n        \"models\": [\"deepseek-chat\", \"deepseek-reasoner\"],\n        \"default_model\": \"deepseek-chat\",\n        \"max_tokens\": 4096,\n        \"temperature\": 0.7\n      },\n      \"anthropic\": {\n        \"api_key\": \"${ANTHROPIC_API_KEY}\",\n        \"base_url\": \"https://api.anthropic.com/v1\",\n        \"models\": [\"claude-sonnet-4-20250514\"],\n        \"max_tokens\": 8192\n      }\n    },\n    \"default_provider\": \"deepseek\"\n  },\n  \"compaction\": {\n    \"window_size\": 20,\n    \"max_tokens\": 100000,\n    \"context_window\": 128000\n  }\n}\n```\n\nObservations:\n1. Database pool_size=10 is reasonable for dev\n2. LLM retry config missing for anthropic\n3. Compaction window_size=20 is fixed strategy"},
  %{role: "user", content: "Security concerns with API keys?"}
]

# 场景 5: 纯英文短文
english_msgs = [
  %{role: "system", content: "You are a helpful assistant."},
  %{role: "user", content: "What is the difference between concurrency and parallelism in programming?"},
  %{role: "assistant", content: "Concurrency is about dealing with multiple things at once, while parallelism is about doing multiple things at once. Concurrency is a design pattern where you structure your program to handle multiple tasks that can make progress without necessarily running simultaneously. Parallelism requires multiple CPU cores to actually execute tasks at the same time."},
  %{role: "user", content: "Can you give an example in Elixir?"}
]

# 场景 6: 单条估算精度（分解验证）
IO.puts("── 单条消息估算分解 ──")
IO.puts("")

test_strings = [
  {"纯中文短句", "你好世界"},
  {"纯英文短句", "hello world"},
  {"中英混合", "Elixir 的 GenServer 是什么？"},
  {"代码片段", "def mount(_params, _session, socket) do\n  {:ok, assign(socket, count: 0)}\nend"},
  {"JSON片段", ~s({"host": "localhost", "port": 5432, "pool_size": 10})},
]

Enum.each(test_strings, fn {name, text} ->
  est = TokenEstimator.estimate(text)
  IO.puts("  #{name}: \"#{String.slice(text, 0, 40)}...\" → 估算 #{est} tokens")
end)
IO.puts("")

# 运行 API 对比测试
results =
  [
    {"场景1: 短对话 (4条)", short_msgs},
    {"场景2: 长对话中英混合 (8条)", long_msgs},
    {"场景3: 工具输出/代码 (4条)", tool_output_msgs},
    {"场景4: JSON密集 (4条)", json_msgs},
    {"场景5: 纯英文 (4条)", english_msgs},
  ]
  |> Enum.map(fn {name, msgs} ->
    TokenTest.run_test(name, msgs, model)
  end)
  |> Enum.reject(&is_nil/1)

IO.puts("=" |> String.duplicate(60))
IO.puts("汇总")
IO.puts("=" |> String.duplicate(60))

Enum.each(results, fn r ->
  status = if r.deviation < 20, do: "✅", else: "❌"
  IO.puts("#{status} #{r.name}: 估算=#{r.estimate} 实际=#{r.actual} 偏差=#{Float.round(r.deviation, 1)}% (#{r.direction})")
end)

avg_dev = Enum.map(results, & &1.deviation) |> Enum.sum() |> Kernel./(max(length(results), 1))
IO.puts("")
IO.puts("平均偏差: #{Float.round(avg_dev, 1)}%")
IO.puts("")

if avg_dev < 20 do
  IO.puts("✅ 整体精度可接受，适合用于 token 预算策略")
else
  IO.puts("❌ 整体精度不足，需要进一步校准系数")
  IO.puts("   建议：调整 CJK 系数（当前 2.0）或英文单词系数（当前 1.3）")
end
