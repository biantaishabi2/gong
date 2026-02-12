#!/usr/bin/env bash
# BDD 门禁脚本 — CI 中运行 bddc 编译检查 + BDD 生成测试
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY_MODULE="Gong.BDD.InstructionRegistry"
RUNTIME_MODULE="Gong.BDD.Instructions.V1"
TEST_CASE="ExUnit.Case"
MODULE_PREFIX="Gong.BDD.Generated"
DOCS_ROOT="docs/bdd"
DSL_IN="docs/bdd"
OUT="test/bdd_generated"

cd "$PROJECT_ROOT"

echo "=== [1/3] bddc check（注册表 + DSL 编译检查）==="
bddc check \
  --project-root "$PROJECT_ROOT" \
  --registry-module "$REGISTRY_MODULE" \
  --runtime-module "$RUNTIME_MODULE" \
  --test-case "$TEST_CASE" \
  --module-prefix "$MODULE_PREFIX" \
  --docs-root "$DOCS_ROOT" \
  --in "$DSL_IN" \
  --out "$OUT"

echo ""
echo "=== [2/3] mix compile（确保生成的测试文件可编译）==="
mix compile --warnings-as-errors

echo ""
echo "=== [3/3] mix test（运行 BDD 生成测试）==="
mix test "$OUT/" --trace

echo ""
echo "=== BDD 门禁通过 ==="
