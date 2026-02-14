# RPC 模式 BDD 测试
# 覆盖 JSON-RPC 解析、分发、错误处理

# ══════════════════════════════════════════════
# Group 1: JSON-RPC 协议（5 场景）
# ══════════════════════════════════════════════

[SCENARIO: RPC-001] TITLE: 解析有效 JSON-RPC 请求 TAGS: unit rpc
GIVEN create_temp_dir
WHEN parse_rpc_request json="{\"jsonrpc\":\"2.0\",\"method\":\"chat\",\"params\":{},\"id\":1}"
THEN assert_rpc_parsed method="chat"

[SCENARIO: RPC-002] TITLE: 解析无效 JSON 返回错误 TAGS: unit rpc
GIVEN create_temp_dir
WHEN parse_rpc_request json="not json"
THEN assert_rpc_error code=-32700

[SCENARIO: RPC-003] TITLE: 分发到已注册方法 TAGS: unit rpc
GIVEN create_temp_dir
WHEN rpc_dispatch method="echo" params="{\"msg\":\"hello\"}"
THEN assert_rpc_result contains="hello"

[SCENARIO: RPC-004] TITLE: 分发到不存在方法 TAGS: unit rpc
GIVEN create_temp_dir
WHEN rpc_dispatch_missing method="nonexistent"
THEN assert_rpc_error code=-32601

[SCENARIO: RPC-005] TITLE: 完整 handle 调用流程 TAGS: unit rpc
GIVEN create_temp_dir
WHEN rpc_handle json="{\"jsonrpc\":\"2.0\",\"method\":\"echo\",\"params\":{\"msg\":\"test\"},\"id\":42}"
THEN assert_rpc_response_json contains="test"
