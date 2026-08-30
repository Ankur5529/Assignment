#!/usr/bin/env bash
# =============================================================================
# scripts/cycle.sh  — Component B: Cycle Harness
# =============================================================================
# Usage: bash scripts/cycle.sh <tier>
#
# Runs the test/fix loop:
#   run gates → if red, build prompt → invoke Dyad (Mode B: write to file, wait
#   for operator) → verify-protected → scan-banned → re-gate → repeat
#
# Hard termination conditions (all non-negotiable):
#   • Max 3 attempts per failure signature
#   • Max 6 total attempts per cycle
#   • Oscillation: same signature returns after a different one → stop at 1 recurrence
#   • No progress: failure count doesn't decrease for 2 consecutive attempts
#   • Wall-clock ceiling: CYCLE_MAX_SECONDS (default: 3600)
#
# On escalation: revert to last green commit, log, exit non-zero.
# Never leave a half-fixed tree.
# =============================================================================
set -euo pipefail

TIER="${1:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ─── Configuration ────────────────────────────────────────────────────────────
MAX_ATTEMPTS_PER_SIG=3
MAX_TOTAL_ATTEMPTS=6
MAX_CONSECUTIVE_NO_PROGRESS=2
CYCLE_MAX_SECONDS="${CYCLE_MAX_SECONDS:-3600}"   # 1 hour default

CYCLES_LOG="cycles.jsonl"
PROMPT_FILE="test-results/dyad-prompt.txt"
PRIOR_ATTEMPTS_FILE="test-results/prior-attempts.txt"
GATE_REPORT="test-results/gate-report.json"

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()    { echo "[cycle] $*"; }
warn()   { echo "[cycle] ⚠ $*"; }
fail()   { echo "[cycle] ✗ $*" >&2; }

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u; }

get_commit() {
  git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

get_failure_count() {
  if [[ ! -f "$GATE_REPORT" ]]; then echo 999; return; fi
  node -e "
    const r = require('./$GATE_REPORT');
    const c = r.gates.reduce((n, g) => n + g.failures.length, 0);
  cat > test-results/get-failure-count.js <<EOF
const fs = require('fs');
try {
  const r = JSON.parse(fs.readFileSync('$GATE_REPORT', 'utf8'));
  const c = r.gates.reduce((n, g) => n + g.failures.length, 0);
  console.log(c);
} catch(e) {
  console.log(999);
}
EOF
  $NODE_CMD test-results/get-failure-count.js 2>/dev/null || echo 999
}

get_signature() {
  if [[ ! -f "$GATE_REPORT" ]]; then echo "unknown"; return; fi
  cat > test-results/get-signature.js <<EOF
const fs = require('fs');
try {
  const r = JSON.parse(fs.readFileSync('$GATE_REPORT', 'utf8'));
  console.log(r.failureSignature || 'unknown');
} catch(e) {
  console.log('unknown');
}
EOF
  $NODE_CMD test-results/get-signature.js 2>/dev/null || echo "unknown"
}

get_changed_files() {
  git diff --name-only HEAD~1 HEAD 2>/dev/null || true
}

append_cycle_log() {
  local cycle_num="$1"
  local started_at="$2"
  local tier="$3"
  local sig="$4"
  local attempts="$5"
  local outcome="$6"
  local duration_sec="$7"
  local files_changed="$8"
  local reason="$9"

  local files_json="[$(echo "$files_changed" | tr '\n' ',' | sed 's/,$//' | sed 's/,/","/g' | sed 's/^/"/;s/$/"/' | sed 's/^""$//')]"
  local reason_json="\"$reason\""
  if [[ -z "$reason" ]]; then reason_json="null"; fi

  cat >> "$CYCLES_LOG" <<LOG_EOF
{"cycle":$cycle_num,"startedAt":"$started_at","tier":$tier,"signature":"$sig","attempts":$attempts,"outcome":"$outcome","durationSec":$duration_sec,"filesChanged":$files_json,"reason":$reason_json}
LOG_EOF
  log "Cycle log appended (cycle=$cycle_num outcome=$outcome reason=${reason:-none})"
}

escalate() {
  local reason="$1"
  local green_commit="$2"
  local cycle_num="$3"
  local started_at="$4"
  local attempts="$5"
  local sig="$6"

  fail "ESCALATING: $reason"
  fail "Reverting to last green commit: $green_commit"

  # Revert to green — never leave a half-fixed tree
  git reset --hard "$green_commit" 2>/dev/null || {
    fail "Could not revert — manual intervention required"
  }

  local ended_at
  ended_at="$(timestamp)"
  local duration=0
  # Compute duration
  if command -v python3 &>/dev/null; then
    duration=$(python3 -c "
from datetime import datetime
try:
    s = datetime.fromisoformat('${started_at}'.replace('Z','+00:00'))
    e = datetime.fromisoformat('${ended_at}'.replace('Z','+00:00'))
    print(int((e-s).total_seconds()))
except: print(0)
" 2>/dev/null || echo 0)
  fi

  local files_changed
  files_changed="$(get_changed_files)" || files_changed=""

  append_cycle_log "$cycle_num" "$started_at" "$TIER" "$sig" "$attempts" "escalated" "$duration" "$files_changed" "$reason"

  fail "Escalation complete. Last green: $green_commit. See cycles.jsonl for history."
  exit 1
}

# ─── Mode B: Dyad prompt interaction ────────────────────────────────────────
# Mode B — GUI only: write prompt to file, block for operator, detect file changes
invoke_dyad_mode_b() {
  local cycle_n="$1"
  local max_cycles="$2"
  local prior_file="$3"

  # Build the prompt packet
  bash scripts/build-prompt.sh "$GATE_REPORT" "$cycle_n" "$max_cycles" "$prior_file" > "$PROMPT_FILE"

  echo ""
  echo "================================================================"
  echo "  MODE B — Operator step required"
  echo "================================================================"
  echo "  Prompt written to: $PROMPT_FILE"
  echo ""
  echo "  1. Open $PROMPT_FILE"
  echo "  2. Paste the prompt into Dyad"
  echo "  3. Let Dyad apply its changes"
  echo "  4. Press ENTER here when Dyad is done"
  echo "================================================================"
  echo ""

  # Wait for operator
  read -r -p "[cycle] Press ENTER when Dyad has finished making changes... "
  echo ""
}

# ─── Main loop ────────────────────────────────────────────────────────────────
mkdir -p test-results

CYCLE_NUM="${HARNESS_CYCLE_NUM:-1}"
STARTED_AT="$(timestamp)"
CYCLE_START_EPOCH="$(date +%s 2>/dev/null || echo 0)"
GREEN_COMMIT="$(get_commit)"

log "Starting cycle $CYCLE_NUM (tier=$TIER)"
log "Green commit: $GREEN_COMMIT"
log "Wall-clock limit: ${CYCLE_MAX_SECONDS}s"

export HARNESS_GREEN_COMMIT="$GREEN_COMMIT"

# Clear prior attempts log for this cycle
> "$PRIOR_ATTEMPTS_FILE"

# Track per-cycle state
TOTAL_ATTEMPTS=0
PREV_SIGNATURE=""
PREV_FAILURE_COUNT=999
NO_PROGRESS_STREAK=0
declare -A SIG_ATTEMPT_COUNT

# ─── Initial gate run ────────────────────────────────────────────────────────
log "Running initial gates (tier $TIER)..."
GATE_PASSED=false
if bash scripts/gate.sh "$TIER" 2>&1; then
  GATE_PASSED=true
fi

node scripts/gate-report.mjs "$TIER" 2>/dev/null || true

if [[ "$GATE_PASSED" == "true" ]]; then
  CURRENT_SIG="$(get_signature)"
  ENDED_AT="$(timestamp)"
  DURATION=$(( $(date +%s 2>/dev/null || echo 0) - CYCLE_START_EPOCH ))
  FILES_CHANGED="$(get_changed_files)"
  append_cycle_log "$CYCLE_NUM" "$STARTED_AT" "$TIER" "$CURRENT_SIG" "0" "green" "$DURATION" "$FILES_CHANGED" ""
  log "Gates already GREEN — nothing to do. Cycle logged."
  exit 0
fi

INITIAL_SIGNATURE="$(get_signature)"
CURRENT_SIGNATURE="$INITIAL_SIGNATURE"
CURRENT_FAILURE_COUNT="$(get_failure_count)"

# ─── Fix loop ────────────────────────────────────────────────────────────────
while true; do

  # ── Wall-clock check ──────────────────────────────────────────────────────
  NOW_EPOCH="$(date +%s 2>/dev/null || echo 0)"
  ELAPSED=$(( NOW_EPOCH - CYCLE_START_EPOCH ))
  if [[ $ELAPSED -ge $CYCLE_MAX_SECONDS ]]; then
    escalate "Wall-clock ceiling exceeded (${ELAPSED}s >= ${CYCLE_MAX_SECONDS}s)" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  # ── Total attempt cap ─────────────────────────────────────────────────────
  if [[ $TOTAL_ATTEMPTS -ge $MAX_TOTAL_ATTEMPTS ]]; then
    escalate "Total attempt cap reached ($TOTAL_ATTEMPTS/$MAX_TOTAL_ATTEMPTS)" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  # ── Per-signature attempt cap ─────────────────────────────────────────────
  SIG_COUNT="${SIG_ATTEMPT_COUNT[$CURRENT_SIGNATURE]:-0}"
  if [[ $SIG_COUNT -ge $MAX_ATTEMPTS_PER_SIG ]]; then
    escalate "Per-signature attempt cap reached ($SIG_COUNT/$MAX_ATTEMPTS_PER_SIG) for signature $CURRENT_SIGNATURE" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  # ── Oscillation check ─────────────────────────────────────────────────────
  if [[ -n "$PREV_SIGNATURE" ]] && \
     [[ "$PREV_SIGNATURE" != "$CURRENT_SIGNATURE" ]] && \
     [[ "${SIG_ATTEMPT_COUNT[$CURRENT_SIGNATURE]:-0}" -ge 1 ]]; then
    escalate "Oscillation detected — signature $CURRENT_SIGNATURE returned after $PREV_SIGNATURE" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  # ── No-progress check ─────────────────────────────────────────────────────
  if [[ "$CURRENT_FAILURE_COUNT" -ge "$PREV_FAILURE_COUNT" ]] && [[ $TOTAL_ATTEMPTS -gt 0 ]]; then
    NO_PROGRESS_STREAK=$(( NO_PROGRESS_STREAK + 1 ))
    warn "No progress streak: $NO_PROGRESS_STREAK (failures: $CURRENT_FAILURE_COUNT vs prev: $PREV_FAILURE_COUNT)"
    if [[ $NO_PROGRESS_STREAK -ge $MAX_CONSECUTIVE_NO_PROGRESS ]]; then
      escalate "No progress for $NO_PROGRESS_STREAK consecutive attempts (failure count: $CURRENT_FAILURE_COUNT)" \
        "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
    fi
  else
    NO_PROGRESS_STREAK=0
  fi

  # ── Increment counters ────────────────────────────────────────────────────
  TOTAL_ATTEMPTS=$(( TOTAL_ATTEMPTS + 1 ))
  SIG_ATTEMPT_COUNT["$CURRENT_SIGNATURE"]=$(( SIG_COUNT + 1 ))
  PREV_SIGNATURE="$CURRENT_SIGNATURE"
  PREV_FAILURE_COUNT="$CURRENT_FAILURE_COUNT"

  log "Attempt $TOTAL_ATTEMPTS (sig_attempts=${SIG_ATTEMPT_COUNT[$CURRENT_SIGNATURE]}/$MAX_ATTEMPTS_PER_SIG, total=$TOTAL_ATTEMPTS/$MAX_TOTAL_ATTEMPTS)"

  # ── Record prior attempt ──────────────────────────────────────────────────
  echo "Attempt $TOTAL_ATTEMPTS on sig $CURRENT_SIGNATURE: $(get_failure_count) failures" >> "$PRIOR_ATTEMPTS_FILE"

  # ── Invoke Dyad (Mode B) ──────────────────────────────────────────────────
  invoke_dyad_mode_b "$TOTAL_ATTEMPTS" "$MAX_TOTAL_ATTEMPTS" "$PRIOR_ATTEMPTS_FILE"

  # ── Post-Dyad safety checks ───────────────────────────────────────────────
  log "Running post-Dyad safety checks..."

  if ! bash scripts/verify-protected.sh 2>&1; then
    fail "verify-protected.sh failed — IMMEDIATE ESCALATION"
    escalate "Dyad modified protected paths (e2e/, scripts/, gate configs)" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  if ! bash scripts/scan-banned.sh 2>&1; then
    fail "scan-banned.sh failed — IMMEDIATE ESCALATION"
    escalate "Dyad introduced banned patterns (@ts-ignore, as any, test.skip, etc.)" \
      "$GREEN_COMMIT" "$CYCLE_NUM" "$STARTED_AT" "$TOTAL_ATTEMPTS" "$CURRENT_SIGNATURE"
  fi

  # Auto-commit Dyad's changes
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "fix(dyad): cycle $CYCLE_NUM attempt $TOTAL_ATTEMPTS"
    log "Dyad changes committed: $(get_commit)"
  else
    warn "Dyad made no file changes"
  fi

  # ── Re-gate ───────────────────────────────────────────────────────────────
  log "Re-running gates (tier $TIER)..."
  GATE_PASSED=false
  if bash scripts/gate.sh "$TIER" 2>&1; then
    GATE_PASSED=true
  fi
  node scripts/gate-report.mjs "$TIER" 2>/dev/null || true

  CURRENT_SIGNATURE="$(get_signature)"
  CURRENT_FAILURE_COUNT="$(get_failure_count)"

  # ── Green? ────────────────────────────────────────────────────────────────
  if [[ "$GATE_PASSED" == "true" ]]; then
    ENDED_AT="$(timestamp)"
    DURATION=$(( $(date +%s 2>/dev/null || echo 0) - CYCLE_START_EPOCH ))
    FILES_CHANGED="$(get_changed_files)"
    append_cycle_log "$CYCLE_NUM" "$STARTED_AT" "$TIER" "$INITIAL_SIGNATURE" \
      "$TOTAL_ATTEMPTS" "green" "$DURATION" "$FILES_CHANGED" ""
    log "CYCLE $CYCLE_NUM COMPLETE — GREEN after $TOTAL_ATTEMPTS attempt(s)"
    exit 0
  fi

  log "Still red (failures: $CURRENT_FAILURE_COUNT, sig: $CURRENT_SIGNATURE)"

done
