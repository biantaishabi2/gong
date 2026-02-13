defmodule Gong.PathUtils do
  @moduledoc """
  统一路径规范化。

  处理 ~、相对路径、.、.. 以及 macOS NFD 变体。
  """

  @doc "规范化路径"
  @spec normalize(String.t()) :: String.t()
  def normalize(path) do
    path
    |> expand_home()
    |> Path.expand()
    |> normalize_unicode()
  end

  # ── 内部 ──

  # 展开 ~ 为用户主目录
  defp expand_home("~/" <> rest) do
    Path.join(System.user_home!(), rest)
  end

  defp expand_home("~") do
    System.user_home!()
  end

  defp expand_home(path), do: path

  # macOS NFD → NFC 规范化
  defp normalize_unicode(path) do
    :unicode.characters_to_nfc_binary(path)
  end
end
