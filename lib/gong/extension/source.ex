defmodule Gong.Extension.Source do
  @moduledoc """
  扩展来源路径的归一化与分类。

  处理 git URL 后缀、本地路径识别、@ 前缀归一化、
  CLI/settings.json 路径合并等。
  """

  @doc """
  归一化 git URL：移除尾部 .git 后缀。

  ## 示例

      iex> Gong.Extension.Source.normalize_git_url("https://github.com/foo/bar.git")
      "https://github.com/foo/bar"

      iex> Gong.Extension.Source.normalize_git_url("https://github.com/foo/bar")
      "https://github.com/foo/bar"
  """
  @spec normalize_git_url(String.t()) :: String.t()
  def normalize_git_url(url) when is_binary(url) do
    String.replace_suffix(url, ".git", "")
  end

  @doc """
  判断路径是否为本地路径。

  以 `.` 开头的路径（如 `.pi/extensions`、`./foo`、`../bar`）
  均识别为本地路径。绝对路径（以 `/` 开头）也视为本地。

  ## 示例

      iex> Gong.Extension.Source.local_path?(".pi/extensions")
      true

      iex> Gong.Extension.Source.local_path?("./relative")
      true

      iex> Gong.Extension.Source.local_path?("https://github.com/foo")
      false
  """
  @spec local_path?(String.t()) :: boolean()
  def local_path?(path) when is_binary(path) do
    cond do
      String.starts_with?(path, ".") -> true
      String.starts_with?(path, "/") -> true
      String.starts_with?(path, "~") -> true
      true -> false
    end
  end

  @doc """
  合并 CLI 参数和 settings.json 中的扩展路径。

  两个来源的路径去重后合并，CLI 参数优先（排在前面）。

  ## 示例

      iex> Gong.Extension.Source.merge_paths(["./a", "./b"], ["./b", "./c"])
      ["./a", "./b", "./c"]
  """
  @spec merge_paths([String.t()], [String.t()]) :: [String.t()]
  def merge_paths(cli_paths, settings_paths)
      when is_list(cli_paths) and is_list(settings_paths) do
    (cli_paths ++ settings_paths)
    |> Enum.uniq()
  end

  @doc """
  归一化 `@` 前缀路径。

  `@scope/package` 风格路径转为标准包名形式（去掉 @ 前缀）。

  ## 示例

      iex> Gong.Extension.Source.normalize_at_prefix("@anthropic/claude-ext")
      "anthropic/claude-ext"

      iex> Gong.Extension.Source.normalize_at_prefix("normal-package")
      "normal-package"
  """
  @spec normalize_at_prefix(String.t()) :: String.t()
  def normalize_at_prefix("@" <> rest), do: rest
  def normalize_at_prefix(path), do: path
end
