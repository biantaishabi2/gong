defmodule Gong do
  @moduledoc """
  Gong (工) — 通用 Agent 引擎。

  基于 Jido + jido_ai + ReqLLM 构建的自主代理框架，
  利用 OTP 提供进程隔离、容错和并发能力。

  ## 架构

  - `Gong.Agent` — Jido Agent 定义，持有工具集和状态
  - `Gong.Tools.*` — 7 个 Jido Action 模块（read/write/edit/bash/grep/find/ls）
  - `Gong.Tape.*` — 会话存储层（文件夹 + SQLite 索引）
  - `Gong.Compaction` — 上下文压缩（滑动窗口 + 摘要）
  - `Gong.Truncate` — 输出截断系统（head/tail/line 三策略）
  """
end
