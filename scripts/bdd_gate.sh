#!/usr/bin/env bash
# BDD 门禁脚本 — CI 中运行 bddc 编译检查 + BDD 生成测试
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== [1/3] bddc check（注册表 + DSL 编译检查）==="
bddc check

echo ""
echo "=== [2/3] mix compile（确保生成的测试文件可编译）==="
mix compile --warnings-as-errors

echo ""
echo "=== [3/3] mix test（运行 BDD 生成测试）==="
mix test test/bdd_generated/ --trace

echo ""
echo "=== BDD 门禁通过 ==="
