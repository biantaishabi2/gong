#!/usr/bin/env bash
set -euo pipefail

# Niuma 集成 gate：编译 + BDD 测试。
export MIX_ENV="${MIX_ENV:-test}"

mix deps.get
mix compile --warnings-as-errors

# BDD 门禁（DSL 编译 + 注解检查）
if command -v bddc &>/dev/null; then
  bddc check --project-root . --in docs/bdd --out test/bdd_generated --skip-bdd-test
fi

# 只跑 BDD 生成测试
mix test test/bdd_generated
