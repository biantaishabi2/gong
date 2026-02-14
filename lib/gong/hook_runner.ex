defmodule Gong.HookRunner do
  @moduledoc """
  Hook 执行引擎。

  提供三种执行模式：
  - `pipe/4` — 串联执行变换型 hook，每个 hook 的输出作为下一个的输入
  - `gate/3` — 拦截型 hook，任一阻止即停止
  - `pipe_input/3` — on_input 特殊处理，支持 :handled 短路
  """

  require Logger

  @hook_timeout 5_000

  @doc """
  串联执行变换型 hook。

  遍历 hooks 列表，依次调用 callback，将上一次的结果作为下一次的第一个参数。
  hook 不实现该回调时跳过。异常时记录错误并跳过该 hook。
  """
  @spec pipe([module()], atom(), term(), [term()]) :: term()
  def pipe(hooks, callback, initial, extra_args \\ [])
  def pipe([], _callback, initial, _extra_args), do: initial

  def pipe(hooks, callback, initial, extra_args) do
    Enum.reduce(hooks, initial, fn hook, acc ->
      if has_callback?(hook, callback, 1 + length(extra_args)) do
        safe_call(hook, callback, extra_args ++ [acc])
        |> case do
          {:ok, result} -> result
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  @doc """
  拦截型 hook 执行。

  遍历 hooks 列表，依次调用 callback。任一返回非 :ok 值即停止。
  返回 :ok 或 {:blocked, reason}。
  """
  @spec gate([module()], atom(), [term()]) :: :ok | {:blocked, String.t()}
  def gate([], _callback, _args), do: :ok

  def gate(hooks, callback, args) do
    arity = length(args)

    Enum.reduce_while(hooks, :ok, fn hook, _acc ->
      if has_callback?(hook, callback, arity) do
        case safe_call(hook, callback, args) do
          {:ok, :ok} ->
            {:cont, :ok}

          {:ok, {:block, reason}} ->
            {:halt, {:blocked, reason}}

          {:ok, :cancel} ->
            {:halt, {:blocked, "cancelled"}}

          {:error, _} ->
            # hook 异常不阻止执行，继续下一个
            {:cont, :ok}

          _ ->
            # hook 返回了非预期值，忽略并继续
            {:cont, :ok}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  @doc """
  on_input 专用管道，支持 :handled 短路。

  返回 {:transform, text, images} | :passthrough | :handled
  """
  @spec pipe_input([module()], String.t(), [map()]) ::
          {:transform, String.t(), [map()]} | :passthrough | :handled
  def pipe_input([], _text, _images), do: :passthrough

  def pipe_input(hooks, text, images) do
    Enum.reduce_while(hooks, {text, images}, fn hook, {cur_text, cur_images} ->
      if has_callback?(hook, :on_input, 2) do
        case safe_call(hook, :on_input, [cur_text, cur_images]) do
          {:ok, {:transform, new_text, new_images}} ->
            {:cont, {new_text, new_images}}

          {:ok, :handled} ->
            {:halt, :handled}

          {:ok, :passthrough} ->
            {:cont, {cur_text, cur_images}}

          {:error, _} ->
            {:cont, {cur_text, cur_images}}
        end
      else
        {:cont, {cur_text, cur_images}}
      end
    end)
    |> case do
      :handled -> :handled
      {^text, ^images} -> :passthrough
      {new_text, new_images} -> {:transform, new_text, new_images}
    end
  end

  @doc """
  on_before_agent 专用管道。

  串联调用各 hook 的 on_before_agent(prompt, system)，
  返回 {prompt, system, extra_messages}。
  """
  @spec pipe_before_agent([module()], String.t(), String.t()) ::
          {String.t(), String.t(), [map()]}
  def pipe_before_agent([], prompt, system), do: {prompt, system, []}

  def pipe_before_agent(hooks, prompt, system) do
    Enum.reduce(hooks, {prompt, system, []}, fn hook, {p, s, extras} ->
      if has_callback?(hook, :on_before_agent, 2) do
        case safe_call(hook, :on_before_agent, [p, s]) do
          {:ok, {new_p, new_s, new_extras}} when is_list(new_extras) ->
            {new_p, new_s, extras ++ new_extras}

          {:error, _} ->
            {p, s, extras}

          _ ->
            {p, s, extras}
        end
      else
        {p, s, extras}
      end
    end)
  end

  @doc "深拷贝消息列表，防止 hook 修改原始数据"
  @spec deep_copy_messages([map()]) :: [map()]
  def deep_copy_messages(messages) when is_list(messages) do
    messages
    |> :erlang.term_to_binary()
    |> :erlang.binary_to_term()
  end

  # ── 安全调用 hook，带超时和异常捕获 ──

  defp safe_call(hook, callback, args) do
    # 临时 trap exits，防止 Task 崩溃传播到调用进程
    old_trap = Process.flag(:trap_exit, true)

    try do
      task = Task.async(fn ->
        apply(hook, callback, args)
      end)

      case Task.yield(task, @hook_timeout) do
        {:ok, result} ->
          {:ok, result}

        {:exit, reason} ->
          # Task 异常退出
          error = %RuntimeError{message: "hook crashed: #{inspect(reason)}"}
          stacktrace = extract_stacktrace(reason)
          emit_hook_error(hook, callback, error, stacktrace)
          {:error, error}

        nil ->
          Task.shutdown(task, :brutal_kill)
          emit_hook_error(hook, callback, %RuntimeError{message: "hook timeout after #{@hook_timeout}ms"}, [])
          {:error, :timeout}
      end
    rescue
      e ->
        emit_hook_error(hook, callback, e, __STACKTRACE__)
        {:error, e}
    catch
      kind, reason ->
        emit_hook_error(hook, callback, %RuntimeError{message: "#{kind}: #{inspect(reason)}"}, __STACKTRACE__)
        {:error, reason}
    after
      # 排空 EXIT 消息并恢复 trap_exit 状态
      drain_exit_messages()
      Process.flag(:trap_exit, old_trap)
    end
  end

  defp drain_exit_messages do
    receive do
      {:EXIT, _, _} -> drain_exit_messages()
    after
      0 -> :ok
    end
  end

  defp extract_stacktrace({_error, stacktrace}) when is_list(stacktrace), do: stacktrace
  defp extract_stacktrace(_), do: []

  # 确保模块已加载后再检查函数是否导出
  defp has_callback?(hook, callback, arity) do
    Code.ensure_loaded(hook)
    function_exported?(hook, callback, arity)
  end

  defp emit_hook_error(hook, callback, error, stacktrace) do
    :telemetry.execute(
      [:gong, :hook, :error],
      %{count: 1},
      %{
        hook: hook,
        callback: callback,
        error: error,
        stacktrace: stacktrace
      }
    )

    Logger.warning("Hook #{inspect(hook)}.#{callback} 异常: #{Exception.message(error)}")
  end
end
