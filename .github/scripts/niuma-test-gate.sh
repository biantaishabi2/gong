#!/usr/bin/env bash
set -euo pipefail

# Niuma 集成 gate：BDD 编译检查 + 全量测试。
export MIX_ENV="${MIX_ENV:-test}"

mix deps.get
mix compile --warnings-as-errors

# BDD 门禁（DSL 编译 + 注解检查）
if command -v bddc &>/dev/null; then
  bddc check --project-root . --in docs/bdd --out test/bdd_generated --skip-bdd-test
fi

# 全量测试（含 BDD 生成测试）
mix test
