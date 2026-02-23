# 模型配置迁移说明

## auth_mode 字段

`auth_mode` 是 `ModelRegistry.model_config` 新增的可选字段，用于指定模型的 API 鉴权方式。

| 值 | 含义 | 注入的 Header |
|---|---|---|
| `:bearer` | OpenAI 兼容鉴权 | `authorization: Bearer <key>` |
| `:anthropic_header` | Anthropic 兼容鉴权 | `x-api-key: <key>` |
| 未设置 | 不注入鉴权头（由下游 ReqLLM.Provider 处理） | 无 |

**重要**：DeepSeek 等已有模型不设置 `auth_mode`，鉴权由 `ReqLLM.Provider` 模块处理，行为与改造前完全一致。

## 新增模型配置

### Kimi (Moonshot)

```elixir
Gong.ModelRegistry.register(:kimi, %{
  provider: "kimi",
  model_id: "moonshot-v1-auto",
  base_url: "https://api.moonshot.cn",
  api_key_env: "KIMI_API_KEY",
  auth_mode: :anthropic_header
})
```

环境变量：`KIMI_API_KEY`

### MiniMax

```elixir
Gong.ModelRegistry.register(:minimax, %{
  provider: "minimax",
  model_id: "minimax-text-01",
  base_url: "https://api.minimax.chat",
  api_key_env: "MINIMAX_API_KEY",
  auth_mode: :anthropic_header
})
```

环境变量：`MINIMAX_API_KEY`

### GLM (智谱)

```elixir
Gong.ModelRegistry.register(:glm, %{
  provider: "glm",
  model_id: "glm-4",
  base_url: "https://open.bigmodel.cn/api/paas/v4",
  api_key_env: "GLM_API_KEY",
  auth_mode: :bearer
})
```

环境变量：`GLM_API_KEY`

## 环境变量要求

使用新模型前，需在部署环境中配置对应的 API Key 环境变量：

```bash
export KIMI_API_KEY="your-kimi-api-key"
export MINIMAX_API_KEY="your-minimax-api-key"
export GLM_API_KEY="your-glm-api-key"
```

如果环境变量未设置，`resolve_config` 不会抛异常，但 headers 中不会包含鉴权头，API 调用将因鉴权失败而报错。

## 回滚步骤

1. 从 `application.ex` 中移除三个 `ModelRegistry.register` 调用
2. 从 `llm_router.ex` 中移除 `inject_auth_header/2` 函数及其调用
3. 从 `model_registry.ex` 中移除 `auth_mode` 类型定义和 `apply_defaults` 中的默认值
4. DeepSeek 行为完全不受影响，无需额外操作
