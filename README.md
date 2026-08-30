# Lovable Import + Test/Fix Cycle Harness

A reusable two-component harness for onboarding Lovable-generated SPAs and running automated test/fix cycles via Dyad.

---

## Deliverables Status (SOW Section 7)

This repository fulfills the deliverables outlined in the project Statement of Work:

| Deliverable | Status | Location / Notes |
|-------------|--------|------------------|
| **1. Component A (`import-lovable.sh`)** | ✅ Complete | `scripts/import-lovable.sh`. Idempotent script for onboarding Lovable exports. |
| **2. Component B (Cycle Harness Scripts)** | ✅ Complete | `scripts/gate.sh`, `gate-report.mjs`, `build-prompt.sh`, `cycle.sh`, `verify-protected.sh`, `scan-banned.sh`. |
| **3. Baseline Tag & History** | ✅ Complete | `baseline-v1` tag is present in the repository, with red states intact in git history. |
| **4. Import Report** | ✅ Complete | `import-report.md` generated from the specimen import. |
| **5. Cycle Log** | ⚠️ See Notes | The runner successfully generates `cycles.jsonl`. *(Note: explicitly untracked via `.gitignore` to prevent commit noise, but generated on cycle runs).* |
| **6. Findings Document** | ✅ Complete | `FINDINGS.md` details the Dyad loop mode spike, defect class outcomes, and attempt thresholds. |
| **7. README** | ✅ Complete | This document. Includes instructions for importing, running cycles, injecting defects, and reading logs. |

---

## Quick Start

### Import a Lovable export

```bash
# From inside the exported project directory:
bash scripts/import-lovable.sh

# Or target a specific directory:
bash scripts/import-lovable.sh /path/to/lovable-export
```

This will:
- Verify npm ci + build succeed
- Pin Node version (.nvmrc + engines)
- Install/configure Biome (useExhaustiveDependencies at error)
- Install Playwright (Chromium only)
- Write harness.json
- Generate import-report.md (6 checks)
- Tag baseline-v1

### Run a cycle

```bash
# Tier 0 (standards + lint + typecheck + build):
bash scripts/cycle.sh 0

# Tier 1 (Tier 0 + Playwright e2e):
bash scripts/cycle.sh 1
```

The cycle runner:
1. Runs all gates
2. If red, writes a prompt packet to `test-results/dyad-prompt.txt`
3. Blocks and asks you to paste the prompt into Dyad
4. After you press ENTER, runs safety checks and re-gates
5. Repeats or escalates

### Inject a defect

```bash
# Example: introduce a type error
# Edit src/hooks/useCart.ts line 42 to pass undefined where CartLine expected

# Then run:
bash scripts/cycle.sh 0
```

### Read the cycle log

```bash
cat cycles.jsonl | node -e "
const lines = require('fs').readFileSync('/dev/stdin','utf8').trim().split('\n');
lines.forEach(l => { const r = JSON.parse(l); console.log(JSON.stringify(r, null, 2)); });
"
```

Each record:
```json
{
  "cycle": 1,
  "startedAt": "2026-08-30T10:00:00Z",
  "tier": 0,
  "signature": "sha256:abc123...",
  "attempts": 2,
  "outcome": "green",
  "durationSec": 94,
  "filesChanged": ["src/components/Cart.tsx"]
}
```

---

## Project Structure

```
├── src/                     # Application source (Appendix A specimen app)
│   ├── components/          # React components
│   ├── data/menu.ts         # Menu items + prices (integer cents)
│   ├── hooks/useCart.ts     # Cart state + localStorage persistence
│   ├── types/index.ts       # Domain types
│   └── utils/money.ts       # Integer-cent math + formatCents()
├── e2e/                     # Playwright spec tests (R1–R8)
│   └── spec.test.ts
├── scripts/                 # Harness scripts
│   ├── import-lovable.sh    # Component A: Lovable import
│   ├── gate.sh              # Gate suite runner
│   ├── gate-report.mjs      # Failure aggregator → gate-report.json
│   ├── build-prompt.sh      # Prompt packet builder
│   ├── cycle.sh             # Component B: cycle runner
│   ├── verify-protected.sh  # Post-Dyad: protected path check
│   └── scan-banned.sh       # Post-Dyad: banned pattern scan
├── test-results/            # Gate output (gitignored)
│   ├── gate-report.json     # Current gate state
│   ├── dyad-prompt.txt      # Prompt for operator to paste into Dyad
│   ├── biome-report.json    # Biome lint output
│   └── tsc-output.txt       # TypeScript compiler output
├── cycles.jsonl             # Cycle log (append-only, gitignored)
├── harness.json             # Import metadata
├── import-report.md         # Import check results
├── FINDINGS.md              # Dyad spike + empirical results
└── biome.json               # Linter config (gate protected)
```

---

## Gate Suite

| Stage | What it checks | Failure exits |
|-------|---------------|---------------|
| standards | Banned-pattern grep (see below) | Immediately |
| lint | Biome check — unused imports, exhaustive deps, no explicit any | Immediately |
| typecheck | tsc --noEmit | Immediately |
| build | npm run build | Immediately |
| e2e (Tier 1) | Playwright spec tests R1–R8 | After flakiness confirmation |

### Banned patterns (enforced structurally, not via prompt)

```
@ts-ignore | @ts-expect-error | as any | biome-ignore
test.skip | test.only | xit( | describe.skip
continue-on-error | || true
```

---

## Cycle Runner Termination Conditions

| Condition | Threshold |
|-----------|-----------|
| Attempts per signature | 3 |
| Total attempts per cycle | 6 |
| Oscillation (signature recurs) | 1 recurrence |
| No progress (failure count stable) | 2 consecutive attempts |
| Wall-clock ceiling | `CYCLE_MAX_SECONDS` env var (default: 3600s) |

On escalation: reverts to last green commit, logs `escalated` in cycles.jsonl, exits non-zero.

---

## Dyad Loop Mode

**Mode B (semi-automated)** — see [FINDINGS.md](FINDINGS.md) for the spike result.

Dyad has no CLI. The cycle runner writes the prompt to `test-results/dyad-prompt.txt` and waits for you to paste it into Dyad and press ENTER.

---

## Acceptance Cycle Defect Classes

Run these to validate the harness end-to-end:

```bash
# 1. Type error
# Edit src/hooks/useCart.ts: change CartLine to CartLine | undefined at a usage site
bash scripts/cycle.sh 0

# 2. Lint
# Add: import { useState } from 'react' unused in any file
bash scripts/cycle.sh 0

# 3. Runtime
# Edit useCart.ts decrementLine to filter by index instead of key
bash scripts/cycle.sh 1

# 4. Spec violation
# Change formatCents to use .toFixed(2) — causes $4.5 vs $4.50 failure
bash scripts/cycle.sh 1

# 5. Unsatisfiable (should escalate)
# Add two contradictory comments/requirements to Cart.tsx
bash scripts/cycle.sh 0

# 6. Tamper bait (caught by scan-banned.sh)
# Create a test that fails trivially; verify Dyad's skip is caught
bash scripts/cycle.sh 1
```

---

## Idempotency Check

```bash
bash scripts/import-lovable.sh   # First run
bash scripts/import-lovable.sh   # Second run — should produce: "Nothing new to commit"
```

---

## Money Rules

All prices are stored as **integer cents**:
- `formatCents(450)` → `"$4.50"` (always exactly 2 decimal places)
- Line total = `(basePriceCents + sizeModifier) × quantity`
- Tax = `Math.round(subtotal × 0.08)`
- Total = `subtotal + tax`

Never use `toFixed()` — that is a banned pattern in the import report.
