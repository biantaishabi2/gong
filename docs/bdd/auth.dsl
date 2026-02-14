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
