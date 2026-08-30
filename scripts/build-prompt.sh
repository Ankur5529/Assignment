#!/usr/bin/env bash
# =============================================================================
# scripts/build-prompt.sh  — Failure → Dyad prompt packet constructor
# =============================================================================
# Usage: bash scripts/build-prompt.sh <gate-report.json> [cycle_n] [max_cycles] [prior_attempts_file]
#
# Emits the structured prompt Dyad receives.
# Advisory constraints only — structural enforcement is in verify-protected.sh
# and scan-banned.sh, which run AFTER every Dyad invocation.
# =============================================================================
set -euo pipefail

export NODE_CMD="${NODE_CMD:-node}"

REPORT="${1:-test-results/gate-report.json}"
CYCLE_N="${2:-1}"
MAX_CYCLES="${3:-6}"
PRIOR_ATTEMPTS_FILE="${4:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[[ -f "$REPORT" ]] || { echo "gate-report.json not found: $REPORT" >&2; exit 1; }

# ─── Parse report fields ──────────────────────────────────────────────────────
TIER=$("$NODE_CMD" -e "const r=require('./$REPORT');console.log(r.tier)")
COMMIT=$("$NODE_CMD" -e "const r=require('./$REPORT');console.log(r.commit)")
SIG=$("$NODE_CMD" -e "const r=require('./$REPORT');console.log(r.failureSignature)")
STATUS=$("$NODE_CMD" -e "const r=require('./$REPORT');console.log(r.status)")

if [[ "$STATUS" == "passed" ]]; then
  echo "[build-prompt] Gates are PASSING — no prompt needed"
  exit 0
fi

# Collect all failures (max 20)
FAILURES=$("$NODE_CMD" -e "
const r = require('./$REPORT');
const all = r.gates.flatMap(g => g.failures.map(f => ({gate: g.gate, ...f})));
const limited = all.slice(0, 20);
limited.forEach(f => console.log(\`\${f.file}:\${f.line} [\${f.code}] \${f.message}\`));
")
FAILURE_COUNT=$(echo "$FAILURES" | grep -c . || echo 0)

# ─── Gather ±15 lines of source context around each distinct failing location ─
CONTEXT=$("$NODE_CMD" -e "
const r = require('./$REPORT');
const fs = require('fs');
const all = r.gates.flatMap(g => g.failures.map(f => ({...f})));
const seen = new Set();
const lines = [];
for (const f of all.slice(0, 20)) {
  const key = f.file + ':' + f.line;
  if (seen.has(key)) continue;
  seen.add(key);
  if (!f.file || !fs.existsSync(f.file)) continue;
  const raw = fs.readFileSync(f.file, 'utf8').split('\n');
  const start = Math.max(0, f.line - 16);
  const end = Math.min(raw.length, f.line + 15);
  lines.push('--- ' + f.file + ' (lines ' + (start+1) + '-' + end + ') ---');
  raw.slice(start, end).forEach((l, i) => {
    const ln = start + i + 1;
    const marker = ln === f.line ? '>>>' : '   ';
    lines.push(marker + ' ' + String(ln).padStart(4) + ' | ' + l);
  });
  lines.push('');
}
console.log(lines.join('\n'));
" 2>/dev/null || echo "(source context unavailable)")

# ─── Prior attempts on this signature ────────────────────────────────────────
PRIOR=""
if [[ -n "$PRIOR_ATTEMPTS_FILE" ]] && [[ -f "$PRIOR_ATTEMPTS_FILE" ]]; then
  PRIOR=$(cat "$PRIOR_ATTEMPTS_FILE")
fi

# ─── Emit prompt packet ───────────────────────────────────────────────────────
cat <<PROMPT_EOF
CYCLE ${CYCLE_N} of ${MAX_CYCLES} — gates failed

Tier: ${TIER}   Commit: ${COMMIT}   Signature: ${SIG}

FAILURES (${FAILURE_COUNT}, first 20):
${FAILURES}

RELEVANT SOURCE:
${CONTEXT}

PRIOR ATTEMPTS ON THIS SIGNATURE:
${PRIOR:-"(none — first attempt on this signature)"}

CONSTRAINTS:
- Do NOT modify: e2e/, scripts/, biome.json, tsconfig.json, playwright.config.*
- Do NOT add: @ts-ignore, @ts-expect-error, \`as any\`, biome-ignore, test.skip, test.only, xit, describe.skip
- Do NOT weaken assertions or reduce assertion count
- Fix the source cause. If a test is genuinely wrong, STOP and say so.
PROMPT_EOF
