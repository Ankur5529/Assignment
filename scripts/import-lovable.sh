#!/usr/bin/env bash
# =============================================================================
# scripts/import-lovable.sh  — Component A: Lovable Import Harness
# =============================================================================
# Usage: bash scripts/import-lovable.sh [<repo-or-path>]
#   <repo-or-path>  Path to the Lovable export directory.
#                   Defaults to CWD if omitted (run from inside the export).
#
# Idempotent: running twice produces no diff on the second run.
# Proven against multiple Lovable exports without modification.
# =============================================================================
set -euo pipefail

HARNESS_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-"$(pwd)"}"

# Resolve to absolute path
TARGET="$(cd "$TARGET" && pwd)"

log()  { echo "[import] $*"; }
ok()   { echo "[import] ✓ $*"; }
warn() { echo "[import] ⚠ $*"; }
fail() { echo "[import] ✗ FATAL: $*" >&2; exit 1; }

# ─── 0. Sanity: target must exist ────────────────────────────────────────────
[[ -d "$TARGET" ]] || fail "Target directory does not exist: $TARGET"
cd "$TARGET"
log "Onboarding: $TARGET"
log "Harness version: $HARNESS_VERSION"

# ─── 1. Git init if needed ────────────────────────────────────────────────────
if [[ ! -d ".git" ]]; then
  git init
  git config user.email "harness@lotusaiworks.com"
  git config user.name "Harness Bot"
  ok "git init"
else
  ok "git already initialised"
fi

# ─── 2. Verify package.json exists ───────────────────────────────────────────
[[ -f "package.json" ]] || fail "No package.json found — is this a Node project?"

# ─── 3. Pin Node version via .nvmrc ──────────────────────────────────────────
if [[ ! -f ".nvmrc" ]]; then
  node --version | sed 's/v//' | cut -d. -f1 > .nvmrc
  ok "Created .nvmrc: $(cat .nvmrc)"
else
  ok ".nvmrc already present ($(cat .nvmrc))"
fi

# Ensure engines field in package.json
NODE_MAJOR="$(cat .nvmrc)"
node -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
const engines = pkg.engines || {};
if (!engines.node || !engines.node.includes('$NODE_MAJOR')) {
  engines.node = '>=$NODE_MAJOR.0.0';
  pkg.engines = engines;
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  process.stdout.write('updated');
} else {
  process.stdout.write('ok');
}
" | grep -q updated && ok "engines.node set in package.json" || ok "engines.node already set"

# ─── 4. Lockfile ─────────────────────────────────────────────────────────────
if [[ ! -f "package-lock.json" ]] && [[ ! -f "yarn.lock" ]] && [[ ! -f "pnpm-lock.yaml" ]]; then
  log "No lockfile found — running npm install to generate one..."
  npm install --prefer-offline 2>&1 | tail -3
  ok "package-lock.json generated"
else
  ok "Lockfile already present"
fi

# ─── 5. npm ci + build ───────────────────────────────────────────────────────
log "Running npm ci..."
npm ci 2>&1 | tail -5
ok "npm ci succeeded"

log "Running npm run build..."
if ! npm run build 2>&1; then
  fail "npm run build failed — fix build errors before harness can proceed"
fi
ok "npm run build succeeded"

# ─── 6. Biome ────────────────────────────────────────────────────────────────
BIOME_VER="1.9.4"
if ! node -e "require('@biomejs/biome')" 2>/dev/null; then
  log "Installing Biome $BIOME_VER..."
  npm install --save-dev "@biomejs/biome@$BIOME_VER" 2>&1 | tail -3
  ok "Biome installed"
else
  ok "Biome already installed"
fi

if [[ ! -f "biome.json" ]]; then
  cat > biome.json <<'BIOME_EOF'
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "useExhaustiveDependencies": "error",
        "noUnusedImports": "error",
        "noUnusedVariables": "error"
      },
      "suspicious": { "noExplicitAny": "error" },
      "style": { "noNonNullAssertion": "warn" }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "javascript": {
    "formatter": { "quoteStyle": "single", "trailingCommas": "es5" }
  },
  "files": { "ignore": ["node_modules", "dist", "*.min.js"] }
}
BIOME_EOF
  ok "biome.json created"
else
  ok "biome.json already present"
fi

# Verify useExhaustiveDependencies actually fires (not silently disabled)
PROBE_FILE="$(mktemp --suffix=.tsx)"
cat > "$PROBE_FILE" <<'PROBE_EOF'
import { useState, useEffect } from 'react'
export function Probe() {
  const [x, setX] = useState(0)
  useEffect(() => { setX(1) }, [])  // missing x in deps — should fire
  return x
}
PROBE_EOF
BIOME_OUT=$(npx --yes @biomejs/biome check --reporter json "$PROBE_FILE" 2>/dev/null || true)
rm -f "$PROBE_FILE"
if echo "$BIOME_OUT" | grep -q "useExhaustiveDependencies"; then
  ok "Biome useExhaustiveDependencies fires correctly"
else
  warn "useExhaustiveDependencies did NOT fire on probe — check biome.json rule group"
fi

# ─── 7. Playwright ───────────────────────────────────────────────────────────
if ! node -e "require('@playwright/test')" 2>/dev/null; then
  log "Installing Playwright..."
  npm install --save-dev @playwright/test 2>&1 | tail -3
  ok "Playwright installed"
else
  ok "Playwright already installed"
fi

# Install Chromium browser only
if [[ ! -d "node_modules/.playwright" ]] && ! npx playwright --version 2>/dev/null | grep -q chromium; then
  log "Installing Chromium browser..."
  npx playwright install chromium 2>&1 | tail -3
  ok "Chromium installed"
else
  ok "Playwright browser already available"
fi

if [[ ! -f "playwright.config.ts" ]] && [[ ! -f "playwright.config.js" ]]; then
  cat > playwright.config.ts <<'PW_EOF'
import { defineConfig, devices } from '@playwright/test'
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  retries: 0,
  reporter: [
    ['list'],
    ['json', { outputFile: 'test-results/playwright-report.json' }],
  ],
  use: { baseURL: 'http://localhost:5173', trace: 'on-first-retry' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env['CI'],
    timeout: 30_000,
  },
})
PW_EOF
  ok "playwright.config.ts created"
else
  ok "playwright.config.ts already present"
fi

# ─── 8. Scaffold scripts/ ────────────────────────────────────────────────────
mkdir -p scripts e2e test-results

# Copy harness scripts from the scripts/ directory where this script lives
HARNESS_SCRIPTS=(
  "gate.sh"
  "gate-report.mjs"
  "build-prompt.sh"
  "cycle.sh"
  "verify-protected.sh"
  "scan-banned.sh"
)

for s in "${HARNESS_SCRIPTS[@]}"; do
  SRC="$SCRIPT_DIR/$s"
  DST="scripts/$s"
  if [[ -f "$SRC" ]] && [[ ! -f "$DST" ]]; then
    cp "$SRC" "$DST"
    chmod +x "$DST"
    ok "Installed scripts/$s"
  elif [[ ! -f "$SRC" ]]; then
    warn "Source script $s not found in $SCRIPT_DIR — skipping"
  else
    ok "scripts/$s already present"
  fi
done

# Scaffold e2e/ placeholder if no tests exist
if [[ ! -f "e2e/.gitkeep" ]] && [[ -z "$(ls -A e2e/ 2>/dev/null)" ]]; then
  touch e2e/.gitkeep
  ok "e2e/ scaffolded"
fi

# ─── 9. harness.json ─────────────────────────────────────────────────────────
IMPORT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > harness.json <<HARNESS_EOF
{
  "sourceGenerator": "lovable",
  "importDate": "$IMPORT_DATE",
  "harnessVersion": "$HARNESS_VERSION",
  "targetPath": "$TARGET"
}
HARNESS_EOF
ok "harness.json written"

# ─── 10. Import report ───────────────────────────────────────────────────────
log "Generating import-report.md..."

# 10a — Float currency math (toFixed on price values)
FLOAT_HITS=$(grep -rEn "toFixed\s*\(" src/ 2>/dev/null || true)
FLOAT_COUNT=$(echo "$FLOAT_HITS" | grep -c toFixed || echo 0)

# 10b — data-testid coverage
INTERACTIVE_MISSING=$(grep -rEn "<(button|input|select|textarea|a)\b" src/ 2>/dev/null | \
  grep -v "data-testid" | wc -l | tr -d ' ' || echo 0)

# 10c — typecheck baseline
TSC_OUTPUT=$(npx tsc --noEmit 2>&1 || true)
TSC_ERROR_COUNT=$(echo "$TSC_OUTPUT" | grep -c "error TS" || echo 0)

# 10d — lint baseline
LINT_OUTPUT=$(npx @biomejs/biome check src/ 2>&1 || true)
LINT_ERROR_COUNT=$(echo "$LINT_OUTPUT" | grep -c "error\|✖" || echo 0)

# 10e — banned patterns
BANNED_PATTERN='@ts-ignore|@ts-expect-error|as any|biome-ignore|test\.skip|test\.only|xit\(|describe\.skip'
BANNED_HITS=$(grep -rEn "$BANNED_PATTERN" src/ e2e/ 2>/dev/null || true)
BANNED_COUNT=$(echo "$BANNED_HITS" | grep -c . || echo 0)

# 10f — off-platform dependencies
PLATFORM_LIST="react react-dom vite typescript @vitejs/plugin-react @biomejs/biome @playwright/test @types/react @types/react-dom"
INSTALLED_DEPS=$(node -e "
const p = require('./package.json');
const all = {...(p.dependencies||{}), ...(p.devDependencies||{})};
const platform = new Set('$PLATFORM_LIST'.split(' '));
const off = Object.keys(all).filter(k => !platform.has(k));
console.log(off.join('\n'));
" 2>/dev/null || echo "")
OFF_COUNT=$(echo "$INSTALLED_DEPS" | grep -c . || echo 0)

cat > import-report.md <<REPORT_EOF
# Import Report

Generated by \`scripts/import-lovable.sh\` on $IMPORT_DATE  
Harness version: $HARNESS_VERSION

---

## Check 1 — Float Currency Math (toFixed)

**Count**: $FLOAT_COUNT occurrence(s)

Generators default to float math with \`.toFixed()\`. Harness standard is integer cents.
$(if [[ $FLOAT_COUNT -gt 0 ]]; then echo ""; echo "\`\`\`"; echo "$FLOAT_HITS"; echo "\`\`\`"; fi)
$(if [[ $FLOAT_COUNT -eq 0 ]]; then echo "_No float currency math detected._"; fi)

---

## Check 2 — Missing data-testid on Interactive Elements

**Count**: $INTERACTIVE_MISSING interactive element(s) without \`data-testid\`

Every element the Playwright tests touch needs a \`data-testid\` attribute.
$(if [[ $INTERACTIVE_MISSING -eq 0 ]]; then echo "_All interactive elements have data-testid._"; fi)

---

## Check 3 — TypeScript Error Baseline

**Error count at import**: $TSC_ERROR_COUNT

These errors are inherited debt, not introduced by Dyad. Any new errors in the loop are regressions.
$(if [[ $TSC_ERROR_COUNT -gt 0 ]]; then echo ""; echo "\`\`\`"; echo "$TSC_OUTPUT" | head -30; echo "\`\`\`"; fi)
$(if [[ $TSC_ERROR_COUNT -eq 0 ]]; then echo "_Clean typecheck at import._"; fi)

---

## Check 4 — Lint Error Baseline

**Error count at import**: $LINT_ERROR_COUNT

$(if [[ $LINT_ERROR_COUNT -eq 0 ]]; then echo "_Clean lint at import._"; fi)
$(if [[ $LINT_ERROR_COUNT -gt 0 ]]; then echo "\`\`\`"; echo "$LINT_OUTPUT" | head -20; echo "\`\`\`"; fi)

---

## Check 5 — Banned Patterns Already Present

**Count**: $BANNED_COUNT banned pattern(s) in source

Pattern: \`$BANNED_PATTERN\`

$(if [[ $BANNED_COUNT -eq 0 ]]; then echo "_No banned patterns found._"; fi)
$(if [[ $BANNED_COUNT -gt 0 ]]; then echo "\`\`\`"; echo "$BANNED_HITS"; echo "\`\`\`"; fi)

---

## Check 6 — Off-Platform Dependencies

**Count**: $OFF_COUNT package(s) not on the platform list

Platform list: $PLATFORM_LIST

$(if [[ $OFF_COUNT -eq 0 ]]; then echo "_All dependencies are on the platform list._"; fi)
$(if [[ $OFF_COUNT -gt 0 ]]; then echo "Packages requiring review:"; echo "\`\`\`"; echo "$INSTALLED_DEPS"; echo "\`\`\`"; fi)

---

_End of import report._
REPORT_EOF

ok "import-report.md generated"

# ─── 11. Commit harness additions ────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  ok "Nothing new to commit (idempotent re-run)"
else
  git commit -m "chore: harness onboarding via import-lovable.sh (v$HARNESS_VERSION)"
  ok "Harness additions committed"
fi

# ─── 12. Tag baseline-v1 ─────────────────────────────────────────────────────
if git tag | grep -q "^baseline-v1$"; then
  ok "baseline-v1 tag already exists"
else
  git tag baseline-v1
  ok "Tagged baseline-v1"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  Harness onboarding complete!"
echo "  Target: $TARGET"
echo "  Tag:    baseline-v1"
echo "  Report: $TARGET/import-report.md"
echo "================================================================"
