defmodule Gong.CompactionE2ETest do
  use ExUnit.Case, async: false

  @moduledoc """
  Compaction E2E 测试 — 真实 LLM 调用 deepseek 生成摘要。

  验证完整压缩链路：
  构造长对话 → AutoCompaction 触发 → Summarizer 调用 LLM → 结构化摘要输出

  需要 DEEPSEEK_API_KEY 环境变量。
  运行方式：mix test --include e2e test/gong/compaction_e2e_test.exs
  """

  @moduletag :e2e

  # 构造一段关于"重构用户认证模块"的多轮编程对话
  # 25 轮对话确保超过 window_size=20，内容总 token > 阈值
  defp build_long_conversation do
    [
      %{role: "user", content: "我需要重构用户认证模块，当前使用 JWT，想迁移到 session-based 认证。项目用的是 Phoenix 框架。"},
      %{role: "assistant", content: "好的，我来帮你规划认证模块重构。首先需要了解当前的 JWT 实现：token 存储位置、过期策略、refresh token 机制。session-based 方案需要考虑 ETS/Redis 存储、并发会话限制、CSRF 防护。"},
      %{role: "user", content: "当前 JWT 存在 localStorage，过期时间 24 小时，没有 refresh token。我想用 ETS 存储 session。"},
      %{role: "assistant", content: "明白了。迁移计划：\n1. 创建 SessionStore GenServer（ETS backend）\n2. 添加 session 生命周期管理（创建/验证/销毁/过期清理）\n3. 修改 AuthPlug 从 JWT 校验改为 session 校验\n4. 前端从 localStorage 改为 httpOnly cookie\n5. 添加 CSRF token 防护\n\n先从 SessionStore 开始实现。"},
      %{role: "user", content: "好的，先实现 SessionStore。要支持多设备登录，每个用户最多 5 个并发会话。"},
      %{role: "assistant", content: "我来创建 SessionStore 模块。使用 ETS 表 :session_store，键为 session_id，值为 session 数据。\n\n已创建 lib/auth/session_store.ex：\n- init/0 创建 ETS 表\n- create/2 创建新 session，检查并发数限制\n- validate/1 验证 session 有效性\n- destroy/1 销毁指定 session\n- cleanup_expired/0 清理过期 session\n- 并发限制：用 match_spec 查询同一 user_id 的 session 数量"},
      %{role: "user", content: "看起来不错。但是我想加上设备信息记录，每个 session 需要存储 user_agent 和 ip 地址。"},
      %{role: "assistant", content: "好的，我更新了 session 数据结构，现在包含：\n- session_id（UUID）\n- user_id\n- user_agent（设备/浏览器信息）\n- ip_address（登录 IP）\n- created_at\n- last_active_at\n- expires_at\n\ncreate/2 改为 create/4，增加 user_agent 和 ip_address 参数。同时添加了 list_user_sessions/1 用于查看用户所有活跃会话。"},
      %{role: "user", content: "好。现在实现 AuthPlug，需要从 cookie 中读取 session_id。"},
      %{role: "assistant", content: "已创建 lib/auth/auth_plug.ex。核心逻辑：\n1. 从请求 cookie 中读取 _session_id\n2. 调用 SessionStore.validate/1 验证\n3. 有效：将 user_id 注入 conn.assigns\n4. 无效/过期：返回 401\n5. 每次请求更新 last_active_at\n\n同时添加了 CSRF 防护：生成 csrf_token 存入 session，验证 POST 请求的 X-CSRF-Token header。"},
      %{role: "user", content: "CSRF 防护的实现有问题，应该用 Phoenix 内置的 Plug.CSRFProtection 而不是自己写。"},
      %{role: "assistant", content: "你说得对，我移除了自定义 CSRF 实现，改用 Phoenix 内置方案：\n1. 在 endpoint.ex 中确保 Plug.Session 和 Plug.CSRFProtection 正确配置\n2. AuthPlug 只负责 session 验证，不再处理 CSRF\n3. cookie 设置为 httpOnly + secure + SameSite=Lax\n\n关键决策：CSRF 防护由框架层处理，认证模块保持单一职责。"},
      %{role: "user", content: "好。现在需要写迁移脚本，让已登录的 JWT 用户平滑过渡到 session 认证。"},
      %{role: "assistant", content: "迁移策略设计：\n\n阶段一（双模式并行，2周）：\n- AuthPlug 先检查 session cookie，无效则回退检查 JWT\n- JWT 验证通过后自动创建 session 并种 cookie\n- 记录 JWT 用量指标\n\n阶段二（仅 session）：\n- 移除 JWT 回退逻辑\n- 清理 JWT 相关代码和依赖\n\n已创建 lib/auth/migration_plug.ex 实现双模式逻辑。"},
      %{role: "user", content: "迁移脚本看起来可以。现在开始写测试。"},
      %{role: "assistant", content: "我来规划测试覆盖：\n\n1. SessionStore 单元测试：\n- 创建/验证/销毁基本流程\n- 并发会话限制（第6个被拒）\n- 过期清理\n- 设备信息记录\n\n2. AuthPlug 集成测试：\n- 有效 session → 200\n- 无效/过期 session → 401\n- 缺少 cookie → 401\n\n3. MigrationPlug 测试：\n- JWT 用户自动获得 session\n- session 优先于 JWT\n\n已创建 test/auth/session_store_test.exs 和 test/auth/auth_plug_test.exs。"},
      %{role: "user", content: "SessionStore 测试中并发限制的测试用例需要改进，应该测试当超过限制时最旧的 session 被踢掉。"},
      %{role: "assistant", content: "好的改进方案：超过并发限制时不是简单拒绝，而是踢掉最旧的 session（LRU 策略）。\n\n修改了两处：\n1. SessionStore.create/4：超过限制时按 last_active_at 排序，销毁最旧的\n2. 测试用例：创建 6 个 session，验证第 1 个被自动销毁，第 6 个成功创建\n\n关键决策变更：并发限制策略从【拒绝新建】改为【LRU 踢出】。"},
      %{role: "user", content: "很好。现在需要添加 session 活跃度刷新机制，不能每个请求都写 ETS。"},
      %{role: "assistant", content: "优化方案：引入节流更新。\n\n实现：\n- 添加 refresh_interval 配置（默认 5 分钟）\n- validate/1 中检查距离上次更新是否超过 interval\n- 超过才执行 ETS 写入更新 last_active_at\n- 未超过则跳过写入，仍返回 valid\n\n这样高频请求场景下 ETS 写入频率降低约 90%。已更新 SessionStore 和对应测试。"},
      %{role: "user", content: "还需要考虑 session 数据的持久化问题，节点重启后 ETS 数据丢失怎么办？"},
      %{role: "assistant", content: "持久化方案选择：\n\n方案 A: DETS（简单，单节点）\n方案 B: Mnesia（分布式，但运维复杂）\n方案 C: Redis（成熟，但引入外部依赖）\n方案 D: 定期快照到数据库\n\n建议用方案 D：\n- ETS 作为热缓存，处理实时请求\n- 每 10 分钟批量同步到 PostgreSQL sessions 表\n- 节点启动时从 DB 加载活跃 session 到 ETS\n- 结合 Phoenix.PubSub 多节点同步\n\n关键决策：ETS 缓存 + PostgreSQL 持久化的混合方案。"},
      %{role: "user", content: "用方案 D。创建数据库迁移和同步逻辑。"},
      %{role: "assistant", content: "已完成：\n\n1. 数据库迁移 priv/repo/migrations/create_sessions.exs：\n- sessions 表：id, user_id, session_token, user_agent, ip_address, last_active_at, expires_at, timestamps\n- user_id 索引 + session_token 唯一索引\n\n2. Session schema: lib/auth/session.ex\n\n3. SessionStore.Sync 模块：\n- sync_to_db/0: 批量 upsert ETS 中的 session 到 DB\n- load_from_db/0: 启动时从 DB 加载未过期 session\n- 使用 GenServer + Process.send_after 实现 10 分钟定时同步\n\n4. 更新 SessionStore.init/0 调用 load_from_db"},
      %{role: "user", content: "数据库同步逻辑看起来没问题。最后一步，更新 API 文档。"},
      %{role: "assistant", content: "已更新 API 文档：\n\n1. POST /api/auth/login：返回 Set-Cookie header（之前返回 JWT body）\n2. POST /api/auth/logout：清除 session cookie\n3. GET /api/auth/sessions：列出当前用户所有活跃会话\n4. DELETE /api/auth/sessions/:id：主动踢出指定会话\n\n文档已更新到 docs/api/auth.md，包含请求/响应示例和错误码说明。"},
      %{role: "user", content: "全部完成了，帮我总结一下这次重构的关键变更。"}
    ]
  end

  setup do
    api_key = System.get_env("DEEPSEEK_API_KEY")

    if api_key == nil do
      IO.puts("\n⚠️  DEEPSEEK_API_KEY 未设置，E2E 压缩测试将被跳过")
    end

    :ok
  end

  describe "Compaction + 真实 LLM 摘要" do
    test "长对话压缩生成结构化摘要" do
      messages = build_long_conversation()

      # 验证消息量足够触发压缩
      token_count = Gong.Compaction.TokenEstimator.estimate_messages(messages)
      assert token_count > 500, "对话 token 数 #{token_count} 应该足够触发压缩"
      assert length(messages) > 20, "消息数 #{length(messages)} 应超过默认窗口 20"

      # 用真实 LLM 调用 compact
      {compacted, summary} =
        Gong.Compaction.compact(messages,
          window_size: 5,
          max_tokens: 200,
          summarize_fn: &Gong.Compaction.Summarizer.summarize/1
        )

      # 摘要不为空
      assert summary != nil, "摘要不应为 nil"
      assert is_binary(summary), "摘要应为字符串"
      assert String.length(summary) > 50, "摘要长度 #{String.length(summary)} 太短"

      # 压缩后消息数应明显少于原始
      assert length(compacted) < length(messages),
        "压缩后 #{length(compacted)} 条应少于原始 #{length(messages)} 条"

      # 第一条应为摘要消息
      [first | _rest] = compacted
      assert first.role == "system" or first[:role] == "system"
      content = first.content || first[:content]
      assert String.starts_with?(content, "[会话摘要]"), "首条消息应以 [会话摘要] 开头"

      # 摘要应包含关键业务信息（LLM 理解对话后的结构化输出）
      summary_lower = String.downcase(summary)

      assert String.contains?(summary_lower, "session") or
               String.contains?(summary, "会话") or
               String.contains?(summary, "认证"),
             "摘要应包含认证/session 相关内容，实际: #{String.slice(summary, 0, 200)}"
    end

    test "AutoCompaction 完整链路触发真实压缩" do
      messages = build_long_conversation()

      # 用较小的 context_window 确保触发
      result =
        Gong.AutoCompaction.auto_compact(messages,
          context_window: 500,
          reserve_tokens: 100,
          window_size: 5
        )

      assert {:compacted, compacted, summary} = result
      assert is_list(compacted)
      assert is_binary(summary)
      assert length(compacted) < length(messages)

      # 摘要含关键技术决策
      assert String.contains?(summary, "JWT") or
               String.contains?(summary, "session") or
               String.contains?(summary, "Session") or
               String.contains?(summary, "认证"),
             "摘要应涉及 JWT/session 迁移主题，实际: #{String.slice(summary, 0, 200)}"
    end

    test "压缩后摘要可作为后续对话的上下文" do
      messages = build_long_conversation()

      # 第一次压缩
      {compacted, first_summary} =
        Gong.Compaction.compact(messages,
          window_size: 5,
          max_tokens: 200,
          summarize_fn: &Gong.Compaction.Summarizer.summarize/1
        )

      assert first_summary != nil

      # 在压缩后的基础上追加新对话
      new_messages =
        compacted ++
          [
            %{role: "user", content: "session 过期时间配置为多少合适？"},
            %{role: "assistant", content: "建议 session 过期时间设为 7 天，配合 refresh_interval 5 分钟的活跃度更新机制。"},
            %{role: "user", content: "好的，还需要添加强制登出所有设备的功能。"},
            %{role: "assistant", content: "已添加 SessionStore.destroy_all_user_sessions/1，通过 user_id 批量销毁。同时添加了 API 端点 DELETE /api/auth/sessions/all。"}
          ]

      # 第二次压缩（update 模式 — 检测到 [会话摘要] 前缀）
      {type, _prompt} = Gong.Prompt.build_summarize_prompt(new_messages)
      assert type == :update, "包含前次摘要时应为 :update 模式"

      # 验证 update 模式的压缩也能正常工作
      {compacted2, second_summary} =
        Gong.Compaction.compact(new_messages,
          window_size: 3,
          max_tokens: 200,
          summarize_fn: &Gong.Compaction.Summarizer.summarize/1
        )

      assert second_summary != nil
      assert length(compacted2) < length(new_messages)
    end
  end
end
