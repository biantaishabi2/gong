#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
部署前门禁脚本（本地/CI 通用）

用法:
  ./scripts/pre_deploy_check.sh
  ./scripts/pre_deploy_check.sh --bdd-only
  ./scripts/pre_deploy_check.sh --skip-bdd
  ./scripts/pre_deploy_check.sh --skip-compile
  ./scripts/pre_deploy_check.sh --skip-bdd-test
  ./scripts/pre_deploy_check.sh --extra-test "mix test test/some/path_test.exs"
  ./scripts/pre_deploy_check.sh -h|--help

行为:
  1) 默认执行 BDD 门禁：./scripts/bdd_gate.sh
  2) 默认执行编译检查：mix compile --warnings-as-errors
  3) 执行 BDD 集成测试：mix test test/bdd_generated/
  4) 可选执行额外测试命令（EXTRA_TEST_CMD 或 --extra-test）

参数:
  --bdd-only          仅执行 BDD 门禁（跳过 compile 和测试）
  --skip-bdd          跳过 BDD 门禁
  --skip-compile      跳过 compile 检查
  --skip-bdd-test     跳过 BDD 集成测试
  --extra-test CMD    额外测试命令
EOF
}

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_BDD="0"
SKIP_COMPILE="0"
SKIP_BDD_TEST="0"
EXTRA_TEST_CMD="${EXTRA_TEST_CMD:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bdd-only)
      SKIP_COMPILE="1"
      SKIP_BDD_TEST="1"
      shift
      ;;
    --skip-bdd)
      SKIP_BDD="1"
      shift
      ;;
    --skip-compile)
      SKIP_COMPILE="1"
      shift
      ;;
    --skip-bdd-test)
      SKIP_BDD_TEST="1"
      shift
      ;;
    --extra-test)
      EXTRA_TEST_CMD="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if [[ "$SKIP_BDD" != "1" ]]; then
  echo "[pre_deploy] step1: bdd gate"
  ./scripts/bdd_gate.sh
else
  echo "[pre_deploy] step1: skipped bdd gate (--skip-bdd)"
fi

if [[ "$SKIP_COMPILE" != "1" ]]; then
  echo "[pre_deploy] step2: compile check"
  MIX_ENV=test mix compile --warnings-as-errors
else
  echo "[pre_deploy] step2: skipped compile check"
fi

if [[ "$SKIP_BDD_TEST" != "1" ]]; then
  echo "[pre_deploy] step3: BDD integration tests"
  MIX_ENV=test mix test test/bdd_generated/ --trace
else
  echo "[pre_deploy] step3: skipped BDD integration tests"
fi

if [[ -n "$EXTRA_TEST_CMD" ]]; then
  echo "[pre_deploy] step4: extra test"
  echo "[pre_deploy] cmd: ${EXTRA_TEST_CMD}"
  bash -lc "$EXTRA_TEST_CMD"
else
  echo "[pre_deploy] step4: no extra test command"
fi

echo "[pre_deploy] all checks passed"
