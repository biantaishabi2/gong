defmodule Gong.Compaction.TokenEstimatorTest do
  use ExUnit.Case, async: true

  alias Gong.Compaction.TokenEstimator

  # pi-mono bugfix 回归: Token 估算精度
  # 中文按字符计数，英文按空格分词

  describe "estimate/1 基础测试" do
    test "中文纯文本精度" do
      # "你好世界测试" 6 个中文字符，每个 1.2 tokens = 7.2 → 7
      estimate = TokenEstimator.estimate("你好世界测试")
      assert estimate == 7
    end

    test "英文纯文本精度" do
      # "hello world test" 3 个英文单词 × 1.3 = 3.9 → 4
      estimate = TokenEstimator.estimate("hello world test")
      assert estimate == 4
    end

    test "nil 和空字符串" do
      assert TokenEstimator.estimate(nil) == 0
      assert TokenEstimator.estimate("") == 0
    end

    test "连续空格折叠" do
      # "a   b" = 2 words × 1.3 = 2.6 → 3（空格仅分隔单词）
      estimate = TokenEstimator.estimate("a   b")
      assert estimate == 3
    end

    test "换行符单独计数" do
      # "a\nb" = 2 words × 1.3 + 1 newline × 0.5 = 2.6 + 0.5 = 3.1 → 3
      estimate = TokenEstimator.estimate("a\nb")
      assert estimate == 3
    end

    test "ASCII 标点计数" do
      # "a+b" = 2 words × 1.3 + 1 punct × 0.5 = 2.6 + 0.5 = 3.1 → 3
      estimate = TokenEstimator.estimate("a+b")
      assert estimate == 3
    end

    test "中文标点计数" do
      # "你好，世界" = 2 CJK × 1.2 + 1 中文标点 × 0.6 + 2 CJK × 1.2 = 2.4 + 0.6 + 2.4 = 5.4 → 5
      estimate = TokenEstimator.estimate("你好，世界")
      assert estimate == 5
    end
  end

  describe "estimate/1 校准测试" do
    # tiktoken cl100k_base 基准值通过离线测量获得
    # 偏差率 = abs(estimate - actual) / actual

    test "纯中文 ~500 字" do
      # 约 500 个常用汉字 + 中文标点
      text = """
      在当今数字化转型的浪潮中，人工智能技术正在深刻改变着各行各业的运作方式。从制造业的智能工厂到金融领域的风控系统，从医疗健康的辅助诊断到教育行业的个性化学习，\
      人工智能的应用场景不断拓展，其影响力也在持续增长。特别是在自然语言处理领域，大型语言模型的出现标志着一个新时代的开始。这些模型通过在海量文本数据上进行预训练，\
      获得了强大的语言理解和生成能力，能够完成翻译、摘要、问答、代码生成等多种任务。随着技术的不断进步，模型的参数规模从最初的数亿增长到了数千亿甚至更多，\
      性能也随之大幅提升。然而，这种规模的增长也带来了新的挑战，包括计算资源的消耗、训练数据的质量控制、模型输出的可靠性以及伦理和安全方面的考量。\
      研究人员正在积极探索各种方法来应对这些挑战，例如通过模型压缩和量化技术降低部署成本，通过强化学习从人类反馈中提升模型的对齐程度，\
      通过检索增强生成技术提高回答的准确性和时效性。与此同时，开源社区的蓬勃发展也为这一领域注入了新的活力，越来越多的高质量模型和工具被开放共享，\
      推动了整个生态系统的快速发展。展望未来，人工智能技术将继续朝着更加智能、更加可控、更加普惠的方向演进，为人类社会创造更大的价值。\
      在这个过程中，如何平衡技术创新与社会责任，如何确保人工智能的发展始终服务于人类的福祉，将是每一个从业者都需要深入思考的重要课题。\
      科技的进步永无止境，唯有保持开放的心态和严谨的态度，才能在这场技术变革中把握机遇、应对挑战，共同创造一个更加美好的未来。
      """

      estimate = TokenEstimator.estimate(text)
      # deepseek tokenizer 实测基准: 约 650 tokens
      actual = 650
      deviation = abs(estimate - actual) / actual
      assert deviation < 0.15, "纯中文偏差率 #{Float.round(deviation * 100, 1)}% 超过 15% 阈值 (estimate=#{estimate}, actual=#{actual})"
    end

    test "纯英文 ~500 词" do
      text = """
      The rapid advancement of artificial intelligence has transformed the landscape of modern technology in ways that were previously unimaginable. Machine learning algorithms now power everything from recommendation systems on streaming platforms to autonomous vehicles navigating complex urban environments. Natural language processing has reached a level of sophistication that enables seamless human computer interaction through conversational interfaces. Deep learning architectures continue to push the boundaries of what is possible in computer vision enabling accurate object detection facial recognition and medical image analysis. The development of transformer based models has been particularly revolutionary establishing new benchmarks across virtually every natural language processing task. These models leverage self attention mechanisms to capture long range dependencies in sequential data making them exceptionally effective for tasks like translation summarization and question answering. The scaling laws observed in large language models suggest that increasing model size and training data generally leads to improved performance though this relationship is not without diminishing returns. Transfer learning has emerged as a powerful paradigm allowing models pretrained on large general purpose datasets to be fine tuned for specific downstream tasks with relatively small amounts of labeled data. This approach has democratized access to state of the art performance making it possible for researchers and practitioners with limited computational resources to achieve impressive results. Reinforcement learning has also seen significant progress with agents achieving superhuman performance in complex strategic games and showing promise in robotics and resource optimization. The intersection of these various subfields continues to produce exciting innovations from multimodal models that can process text images and audio simultaneously to generative models capable of producing remarkably realistic synthetic content. As these technologies mature the importance of responsible development and deployment becomes increasingly critical. Issues of bias fairness transparency and accountability must be addressed proactively to ensure that artificial intelligence serves the broader interests of society. The research community has responded with growing attention to AI safety alignment and interpretability seeking to develop systems that are not only powerful but also trustworthy and beneficial. Looking ahead the convergence of artificial intelligence with other emerging technologies such as quantum computing and biotechnology promises to unlock entirely new possibilities that we are only beginning to envision. Furthermore the rapid growth of edge computing has enabled artificial intelligence models to run directly on devices such as smartphones wearables and Internet of Things sensors reducing latency and improving privacy by processing data locally rather than sending it to cloud servers. Federated learning represents another promising approach that allows multiple organizations to collaboratively train models without sharing sensitive data addressing critical privacy concerns in healthcare finance and other regulated industries. The emergence of foundation models has also sparked important debates about the concentration of power in artificial intelligence development as training these massive systems requires enormous computational resources that are only available to a handful of well funded organizations. Open source initiatives have partially addressed this imbalance by making pretrained models and training frameworks widely accessible enabling a broader community of researchers developers and organizations to participate in advancing the field. Meanwhile regulatory frameworks around the world are evolving to keep pace with these technological developments with the European Union leading efforts to establish comprehensive artificial intelligence governance through legislation that aims to balance innovation with protection of fundamental rights.
      """

      estimate = TokenEstimator.estimate(text)
      # tiktoken cl100k_base 基准: 约 650 tokens
      actual = 650
      deviation = abs(estimate - actual) / actual
      assert deviation < 0.15, "纯英文偏差率 #{Float.round(deviation * 100, 1)}% 超过 15% 阈值 (estimate=#{estimate}, actual=#{actual})"
    end

    test "Elixir 代码 ~100 行" do
      text = ~S"""
      defmodule MyApp.Accounts do
        @moduledoc "用户账号管理模块"

        import Ecto.Query, warn: false
        alias MyApp.Repo
        alias MyApp.Accounts.{User, Session, Token}

        @max_attempts 5
        @lock_duration_seconds 900

        @doc "根据 ID 获取用户"
        @spec get_user(integer()) :: User.t() | nil
        def get_user(id) when is_integer(id) do
          Repo.get(User, id)
          |> case do
            nil -> {:error, :not_found}
            user -> {:ok, user}
          end
        end

        @doc "根据邮箱获取用户"
        def get_user_by_email(email) when is_binary(email) do
          User
          |> where([u], u.email == ^email)
          |> where([u], u.active == true)
          |> Repo.one()
        end

        @doc "创建新用户"
        def create_user(attrs \\ %{}) do
          %User{}
          |> User.registration_changeset(attrs)
          |> Repo.insert()
          |> case do
            {:ok, user} ->
              user
              |> generate_confirmation_token()
              |> send_confirmation_email()
              {:ok, user}

            {:error, changeset} ->
              {:error, changeset}
          end
        end

        @doc "更新用户资料"
        def update_user(%User{} = user, attrs) do
          user
          |> User.profile_changeset(attrs)
          |> Repo.update()
        end

        @doc "用户登录验证"
        def authenticate(email, password) do
          with {:ok, user} <- get_user_by_email(email) |> wrap_result(),
               :ok <- check_lock_status(user),
               :ok <- verify_password(user, password),
               {:ok, session} <- create_session(user) do
            reset_failed_attempts(user)
            {:ok, %{user: user, session: session, token: session.token}}
          else
            {:error, :locked} = error ->
              error

            {:error, :invalid_credentials} ->
              increment_failed_attempts(email)
              {:error, :invalid_credentials}

            {:error, reason} ->
              {:error, reason}
          end
        end

        defp check_lock_status(%User{locked_until: nil}), do: :ok
        defp check_lock_status(%User{locked_until: locked_until}) do
          if DateTime.compare(DateTime.utc_now(), locked_until) == :gt do
            :ok
          else
            {:error, :locked}
          end
        end

        defp verify_password(%User{password_hash: hash}, password) do
          if Bcrypt.verify_pass(password, hash) do
            :ok
          else
            {:error, :invalid_credentials}
          end
        end

        defp create_session(%User{id: user_id}) do
          token = :crypto.strong_rand_bytes(32) |> Base.url_encode64()
          expires_at = DateTime.utc_now() |> DateTime.add(86_400 * 30, :second)

          %Session{}
          |> Session.changeset(%{
            user_id: user_id,
            token: token,
            expires_at: expires_at,
            ip_address: "127.0.0.1",
            user_agent: "unknown"
          })
          |> Repo.insert()
        end

        defp increment_failed_attempts(email) do
          User
          |> where([u], u.email == ^email)
          |> Repo.one()
          |> case do
            nil -> :ok
            user ->
              attempts = (user.failed_attempts || 0) + 1
              attrs = %{failed_attempts: attempts}
              attrs = if attempts >= @max_attempts do
                locked = DateTime.utc_now() |> DateTime.add(@lock_duration_seconds, :second)
                Map.put(attrs, :locked_until, locked)
              else
                attrs
              end
              update_user(user, attrs)
          end
        end

        defp reset_failed_attempts(%User{} = user) do
          update_user(user, %{failed_attempts: 0, locked_until: nil})
        end

        defp generate_confirmation_token(%User{} = user) do
          token = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
          %Token{user_id: user.id, token: token, type: :confirmation}
          |> Repo.insert!()
          {user, token}
        end

        defp send_confirmation_email({user, token}) do
          MyApp.Mailer.send_confirmation(user.email, token)
          user
        end

        defp wrap_result(nil), do: {:error, :not_found}
        defp wrap_result(user), do: {:ok, user}
      end
      """

      estimate = TokenEstimator.estimate(text)
      # tiktoken cl100k_base 基准: 约 900 tokens
      actual = 900
      deviation = abs(estimate - actual) / actual
      assert deviation < 0.20, "Elixir 代码偏差率 #{Float.round(deviation * 100, 1)}% 超过 20% 阈值 (estimate=#{estimate}, actual=#{actual})"
    end

    test "JSON 工具输出 ~50 个键值对" do
      text = ~S"""
      {
        "response": {
          "status": "success",
          "code": 200,
          "message": "Data retrieved successfully",
          "timestamp": "2024-01-15T10:30:00Z"
        },
        "data": {
          "user": {
            "id": 12345,
            "username": "john_doe",
            "email": "john@example.com",
            "display_name": "John Doe",
            "role": "admin",
            "active": true,
            "created_at": "2023-06-15T08:00:00Z",
            "last_login": "2024-01-14T22:15:30Z",
            "preferences": {
              "theme": "dark",
              "language": "en",
              "timezone": "America/New_York",
              "notifications": {
                "email": true,
                "push": false,
                "sms": false,
                "frequency": "daily"
              }
            },
            "profile": {
              "avatar_url": "https://cdn.example.com/avatars/12345.jpg",
              "bio": "Software engineer with 10 years of experience",
              "location": "New York, NY",
              "company": "Tech Corp",
              "website": "https://johndoe.dev"
            }
          },
          "permissions": [
            "read:users",
            "write:users",
            "delete:users",
            "read:posts",
            "write:posts",
            "admin:settings",
            "manage:roles"
          ],
          "quota": {
            "api_calls_limit": 10000,
            "api_calls_used": 3456,
            "storage_limit_mb": 5120,
            "storage_used_mb": 2048,
            "bandwidth_limit_gb": 100,
            "bandwidth_used_gb": 45
          },
          "recent_activity": [
            {"action": "login", "timestamp": "2024-01-14T22:15:30Z", "ip": "192.168.1.1"},
            {"action": "update_profile", "timestamp": "2024-01-14T20:00:00Z", "ip": "192.168.1.1"},
            {"action": "create_post", "timestamp": "2024-01-13T15:30:00Z", "ip": "10.0.0.5"}
          ]
        },
        "pagination": {
          "page": 1,
          "per_page": 20,
          "total": 1,
          "total_pages": 1
        }
      }
      """

      estimate = TokenEstimator.estimate(text)
      # tiktoken cl100k_base 基准: 约 500 tokens
      actual = 500
      deviation = abs(estimate - actual) / actual
      assert deviation < 0.20, "JSON 偏差率 #{Float.round(deviation * 100, 1)}% 超过 20% 阈值 (estimate=#{estimate}, actual=#{actual})"
    end

    test "中英混合技术文档" do
      text = """
      ## Phoenix LiveView 实时通信架构

      Phoenix LiveView 是 Elixir 生态中最重要的实时 Web 框架之一。它通过 WebSocket 连接实现服务端渲染的实时交互，\
      无需编写 JavaScript 代码即可构建丰富的用户界面。

      ### 核心概念

      1. **Mount 阶段**: 当用户首次访问页面时，`mount/3` callback 被调用。此时 LiveView 进程启动，\
      建立 WebSocket 连接。参数包括 `params`、`session` 和 `socket`。

      2. **Handle Event**: 用户交互（如点击按钮、提交表单）触发 `handle_event/3`。\
      例如：`def handle_event("save", %{"user" => params}, socket)`。

      3. **Handle Info**: 进程间消息通过 `handle_info/2` 处理。常用于 PubSub 订阅：
      ```elixir
      def handle_info({:user_updated, user}, socket) do
        {:noreply, assign(socket, :user, user)}
      end
      ```

      4. **Assign 与 Stream**: `assign/3` 用于存储状态，`stream/4` 用于高效处理大列表。\
      Stream 通过 DOM patching 实现增量更新，避免重新渲染整个列表。

      ### 性能优化建议

      - 使用 `temporary_assigns` 减少内存占用（适用于 feed 类列表）
      - 避免在 `mount/3` 中执行耗时操作，改用 `send(self(), :load_data)` 异步加载
      - 对于频繁更新的数据，使用 `Phoenix.PubSub` 实现 broadcast 机制
      - LiveComponent 用于封装可复用的有状态组件，通过 `update/2` 接收数据更新
      - 使用 `phx-debounce` 和 `phx-throttle` 控制事件触发频率

      ### 部署注意事项

      生产环境需要配置 `check_origin` 和 `secret_key_base`。推荐使用 `fly.io` 或 `Gigalixir` \
      等支持 Elixir 的 PaaS 平台。Cluster 模式下需配置 `libcluster` 实现节点发现，\
      并确保 PubSub adapter 使用 `Phoenix.PubSub.PG2` 以支持分布式消息。
      """

      estimate = TokenEstimator.estimate(text)
      # deepseek tokenizer 实测基准: 约 580 tokens
      actual = 580
      deviation = abs(estimate - actual) / actual
      assert deviation < 0.15, "中英混合偏差率 #{Float.round(deviation * 100, 1)}% 超过 15% 阈值 (estimate=#{estimate}, actual=#{actual})"
    end
  end

  describe "estimate_messages/1" do
    test "消息列表估算" do
      messages = [
        %{content: "你好"},
        %{content: "hello world"}
      ]

      estimate = TokenEstimator.estimate_messages(messages)
      # "你好" = 2 × 1.2 = 2.4 → 2, "hello world" = 1.3 + 1.3 = 2.6 → 3, 总计 5
      assert estimate == 5
    end

    test "空列表" do
      assert TokenEstimator.estimate_messages([]) == 0
    end
  end
end
