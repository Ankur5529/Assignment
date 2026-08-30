#!/usr/bin/env bash
# Usage: bash scripts/gate.sh <tier>
#   tier 0: standards → lint → typecheck → build
#   tier 1: tier 0 + playwright e2e
#
# Exits non-zero on any gate failure. Fail-fast: stops at first failing stage.
set -euo pipefail

TIER="${1:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

pass() { echo "[gate] ✓ $*"; }
fail() { echo "[gate] ✗ FAIL: $*" >&2; exit 1; }
log()  { echo "[gate] → $*"; }


log "Stage: standards"
bash scripts/scan-banned.sh || fail "standards"
pass "standards"


log "Stage: lint"
if ! npx @biomejs/biome check --reporter json src/ > test-results/biome-report.json; then
  # Also write human-readable output for debugging
  npx @biomejs/biome check src/ 2>&1 | tail -20 || true
  fail "lint"
fi
pass "lint"


log "Stage: typecheck"
mkdir -p test-results
if ! npx tsc --noEmit 2> test-results/tsc-output.txt; then
  cat test-results/tsc-output.txt | head -30
  fail "typecheck"
fi
pass "typecheck"


log "Stage: build"
if ! npm run build > test-results/build-output.txt 2>&1; then
  cat test-results/build-output.txt | tail -20
  fail "build"
fi
pass "build"


if [[ "$TIER" -ge 1 ]]; then
  log "Stage: e2e (Playwright)"
  mkdir -p test-results

  # Run e2e twice on first red to weed out flakiness
  if ! npx playwright test --reporter=json,list 2> test-results/playwright-stderr.txt; then
    log "e2e first run failed — re-running to confirm (flakiness check)..."
    if ! npx playwright test --reporter=json,list 2>> test-results/playwright-stderr.txt; then
      cat test-results/playwright-stderr.txt | tail -20
      fail "e2e"
    else
      log "Second e2e run passed — first failure was flaky, ignoring"
    fi
  fi
  pass "e2e"
fi

echo ""
echo "[gate] ALL GATES PASSED (tier $TIER)"
exit 0
