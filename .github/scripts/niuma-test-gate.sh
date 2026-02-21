#!/usr/bin/env bash
set -euo pipefail

# niuma test gate: 运行测试套件作为 PR 合并门禁
echo "=== Niuma Test Gate ==="
echo "Running mix test..."

mix test --color
