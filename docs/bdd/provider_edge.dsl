# Provider 兼容性边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的多厂商 Provider 边界

# ══════════════════════════════════════════════
# Group 1: 错误分类与容错（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROVIDER-ERR-001] TITLE: 非标准 stop_reason 归类为 permanent TAGS: unit retry
GIVEN create_temp_dir
WHEN classify_error error="stop_reason: content_policy violation"
THEN assert_error_class expected="permanent"

[SCENARIO: PROVIDER-ERR-002] TITLE: 厂商不支持的字段自动剥离 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages_with_unsupported_fields count=2 field="store"
WHEN convert_messages from="openai" to="anthropic"
THEN assert_converted_messages count=2
THEN assert_fields_stripped field="store"

# ══════════════════════════════════════════════
# Group 2: 模型与 Provider 联动（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROVIDER-ERR-003] TITLE: 上下文窗口大小按模型动态适配 TAGS: unit config
GIVEN create_temp_dir
GIVEN init_model_registry
GIVEN register_model_with_context_window name="claude3" provider="anthropic" model_id="claude-3-opus" context_window=200000
WHEN switch_model name="claude3"
THEN assert_context_window_size name="claude3" expected=200000

[SCENARIO: PROVIDER-ERR-004] TITLE: Provider 超时选项正确透传到 HTTP 客户端 TAGS: unit provider
GIVEN create_temp_dir
WHEN init_provider_registry
WHEN register_provider_with_timeout name="slow_provider" module="MockProvider" timeout=30000
THEN assert_provider_timeout name="slow_provider" expected=30000

# ══════════════════════════════════════════════
# Group 3: 令牌与消息格式（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: PROVIDER-ERR-005] TITLE: 流中断后令牌统计保留部分数据 TAGS: unit cost
GIVEN create_temp_dir
WHEN init_cost_tracker
WHEN record_partial_llm_call model="claude-3" input_tokens=500 output_tokens=100 reason="abort"
THEN assert_partial_tokens_preserved model="claude-3"
THEN assert_cost_summary call_count=1

[SCENARIO: PROVIDER-ERR-006] TITLE: 跨网关路由 Claude 模型时包含必需 provider 特定字段 TAGS: unit cross_provider
GIVEN create_temp_dir
GIVEN cross_provider_messages_with_gateway provider="anthropic" count=2
WHEN convert_messages from="openai" to="anthropic"
THEN assert_converted_messages count=2
THEN assert_required_fields_added field="anthropic-version"
