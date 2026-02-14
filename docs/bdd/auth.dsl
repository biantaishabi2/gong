# Provider OAuth 认证 BDD 测试
# 覆盖认证方式检测、OAuth 流程、API Key 获取

# ══════════════════════════════════════════════
# Group 1: Provider OAuth（4 场景）
# ══════════════════════════════════════════════

[SCENARIO: AUTH-001] TITLE: API Key 认证方式检测 TAGS: unit auth
GIVEN create_temp_dir
WHEN detect_auth_method provider="deepseek"
THEN assert_auth_method expected="api_key"

[SCENARIO: AUTH-002] TITLE: OAuth 认证方式检测 TAGS: unit auth
GIVEN create_temp_dir
WHEN detect_auth_method provider="anthropic"
THEN assert_auth_method expected="oauth"

[SCENARIO: AUTH-003] TITLE: OAuth 授权 URL 生成 TAGS: unit auth
GIVEN create_temp_dir
WHEN generate_authorize_url client_id="test_client" authorize_url="https://auth.example.com/authorize"
THEN assert_authorize_url contains="client_id=test_client"

[SCENARIO: AUTH-004] TITLE: 授权码交换 token TAGS: unit auth
GIVEN create_temp_dir
WHEN exchange_auth_code code="test_code_123"
THEN assert_auth_token contains="test_code_123"

# ══════════════════════════════════════════════
# Group 2: Auth 补充覆盖（5 场景）
# ══════════════════════════════════════════════

[SCENARIO: AUTH-005] TITLE: 刷新 token TAGS: unit auth
GIVEN create_temp_dir
WHEN refresh_auth_token refresh="mock_refresh_abc"
THEN assert_auth_token contains="refreshed_access"

[SCENARIO: AUTH-006] TITLE: token 过期检测 TAGS: unit auth
GIVEN create_temp_dir
WHEN check_token_expired expires_at=0
THEN assert_token_expired expected="true"

[SCENARIO: AUTH-007] TITLE: token 未过期检测 TAGS: unit auth
GIVEN create_temp_dir
WHEN check_token_expired expires_at=9999999999
THEN assert_token_expired expected="false"

[SCENARIO: AUTH-008] TITLE: 获取 API Key 成功 TAGS: unit auth
GIVEN create_temp_dir
WHEN get_api_key env_var="GONG_TEST_API_KEY"
THEN assert_api_key_result status="ok"

[SCENARIO: AUTH-009] TITLE: 获取 API Key 缺失 TAGS: unit auth
GIVEN create_temp_dir
WHEN get_api_key env_var="GONG_NONEXISTENT_VAR_12345"
THEN assert_api_key_result status="error"
