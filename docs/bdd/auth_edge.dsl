# 认证边界场景 BDD 测试
# 覆盖 pi-mono bugfix 中的认证异常处理

# ══════════════════════════════════════════════
# Group 1: 认证锁文件与环境变量（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: AUTH-ERR-001] TITLE: 认证锁文件损坏时优雅恢复 TAGS: unit auth
GIVEN create_temp_dir
GIVEN create_auth_lock_file content="{\"token\": \"valid\"}"
GIVEN corrupt_auth_lock_file
THEN assert_auth_lock_recovered

[SCENARIO: AUTH-ERR-002] TITLE: API key 环境变量不被全局修改 TAGS: unit auth
GIVEN create_temp_dir
GIVEN set_env_api_key env_var="TEST_API_KEY" value="sk-test-12345"
WHEN get_api_key_via_auth env_var="TEST_API_KEY"
THEN assert_env_unchanged env_var="TEST_API_KEY" expected="sk-test-12345"

# ══════════════════════════════════════════════
# Group 2: 登出与 Token 刷新（2 场景）
# ══════════════════════════════════════════════

[SCENARIO: AUTH-ERR-003] TITLE: 登出后清理模型引用 TAGS: unit auth
GIVEN create_temp_dir
GIVEN init_model_registry
GIVEN register_model name="auth_model" provider="anthropic" model_id="claude-3"
WHEN auth_logout
THEN assert_model_references_cleaned

[SCENARIO: AUTH-ERR-004] TITLE: 长时间运行时 OAuth token 自动刷新 TAGS: unit auth
GIVEN create_temp_dir
GIVEN create_expiring_token expires_in_seconds=5
WHEN simulate_token_check
THEN assert_token_refreshed
