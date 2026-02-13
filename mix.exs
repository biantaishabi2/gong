defmodule Gong.MixProject do
  use Mix.Project

  def project do
    [
      app: :gong,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "Gong",
      description: "通用 Agent 引擎 — 基于 Jido + OTP 的自主代理框架"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Gong.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Agent 框架
      {:jido, "~> 2.0.0-rc.4"},
      {:jido_ai, github: "agentjido/jido_ai", branch: "main"},

      # LLM 客户端
      {:req_llm, "~> 1.5"},

      # 数据库（Tape 存储索引）
      {:ecto_sqlite3, "~> 0.17"},
      {:exqlite, "~> 0.23"},

      # JSON
      {:jason, "~> 1.4"},

      # 开发/测试
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
