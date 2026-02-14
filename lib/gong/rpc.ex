defmodule Gong.RPC do
  @moduledoc """
  JSON-RPC 模式 — 通过 stdin/stdout 提供 Agent 能力。

  支持 JSON-RPC 2.0 协议，用于嵌入其他进程。
  """

  @type request :: %{
          jsonrpc: String.t(),
          method: String.t(),
          params: map(),
          id: term()
        }

  @type response :: %{
          jsonrpc: String.t(),
          result: term(),
          id: term()
        }

  @type error_response :: %{
          jsonrpc: String.t(),
          error: %{code: integer(), message: String.t()},
          id: term()
        }

  # 标准错误码
  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @internal_error -32603

  @doc "解析 JSON-RPC 请求"
  @spec parse_request(String.t()) :: {:ok, request()} | {:error, error_response()}
  def parse_request(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = data} ->
        params = Map.get(data, "params", %{})
        {:ok, %{jsonrpc: "2.0", method: method, params: params, id: id}}

      {:ok, _} ->
        {:error, error_response(nil, @invalid_request, "无效的 JSON-RPC 请求")}

      {:error, _} ->
        {:error, error_response(nil, @parse_error, "JSON 解析失败")}
    end
  end

  @doc "构建成功响应"
  @spec success_response(term(), term()) :: response()
  def success_response(id, result) do
    %{jsonrpc: "2.0", result: result, id: id}
  end

  @doc "构建错误响应"
  @spec error_response(term(), integer(), String.t()) :: error_response()
  def error_response(id, code, message) do
    %{jsonrpc: "2.0", error: %{code: code, message: message}, id: id}
  end

  @doc "分发请求到对应的处理方法"
  @spec dispatch(request(), map()) :: response() | error_response()
  def dispatch(%{method: method, params: params, id: id}, handlers) do
    case Map.get(handlers, method) do
      nil ->
        error_response(id, @method_not_found, "方法不存在: #{method}")

      handler when is_function(handler, 1) ->
        try do
          result = handler.(params)
          success_response(id, result)
        rescue
          e ->
            error_response(id, @internal_error, Exception.message(e))
        end
    end
  end

  @doc "编码响应为 JSON 字符串"
  @spec encode_response(response() | error_response()) :: String.t()
  def encode_response(response) do
    Jason.encode!(response)
  end

  @doc "处理完整的 JSON-RPC 调用流程"
  @spec handle(String.t(), map()) :: String.t()
  def handle(json, handlers) do
    case parse_request(json) do
      {:ok, request} ->
        dispatch(request, handlers)
        |> encode_response()

      {:error, error} ->
        encode_response(error)
    end
  end
end
