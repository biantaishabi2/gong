#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GEN_DIR="${1:-$ROOT_DIR/test/bdd_generated}"

if [[ ! -d "$GEN_DIR" ]]; then
  exit 0
fi

# 统一将生成测试中的绝对 DSL 路径标准化为相对路径，避免不同机器路径导致无意义 diff。
find "$GEN_DIR" -type f -name '*_generated_test.exs' -print0 | while IFS= read -r -d '' file; do
  sed -i "s|$ROOT_DIR/docs/bdd/|docs/bdd/|g" "$file"
done
