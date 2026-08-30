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

# ─── Ensure 'node' is on PATH ─────────────────────────────────────────────────
# On Windows + WSL, node may not be on bash's PATH even if npx is.
if ! command -v node &>/dev/null; then
  # Try to find node next to npx
  NPX_BIN="$(command -v npx 2>/dev/null || true)"
  if [[ -n "$NPX_BIN" ]]; then
    NODE_DIR="$(dirname "$NPX_BIN")"
    if [[ -f "$NODE_DIR/node" ]] || [[ -f "$NODE_DIR/node.exe" ]]; then
      export PATH="$NODE_DIR:$PATH"
    fi
  fi
  # If still not found, try common locations
  for TRY in \
    "/mnt/c/Program Files/nodejs" \
    "/usr/local/bin" \
    "/usr/bin" \
    "$HOME/.nvm/versions/node/$(cat .nvmrc 2>/dev/null || echo 'v20')/bin" \
  ; do
    if [[ -f "$TRY/node" ]] || [[ -f "$TRY/node.exe" ]]; then
      export PATH="$TRY:$PATH"
      break
    fi
  done
fi

if ! command -v node &>/dev/null; then
  echo "[import] WARNING: 'node' not found on PATH — Node.js scripts will use 'npx node'" >&2
  NODE_CMD="npx node"
else
  NODE_CMD="node"
fi

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
$NODE_CMD -e "
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json','utf8'));
const engines = pkg.engines || {};
if (!engines.node || !engines.node.includes('$NODE_MAJOR')) {
  engines.node = '>=$NODE_MAJOR.0.0';
  pkg.engines = engines;
  fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\\n');
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
if ! $NODE_CMD -e "require('@biomejs/biome')" 2>/dev/null; then
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
# Write probe inside src/ so biome.json from project root is picked up
PROBE_FILE="src/__biome_probe__.tsx"
cat > "$PROBE_FILE" <<'PROBE_EOF'
import { useEffect } from 'react'
export function Probe({ count }: { count: number }) {
  useEffect(() => {
    console.log(count)
  }, [])
  return count
}
PROBE_EOF
BIOME_OUT=$(npx @biomejs/biome check --reporter json "$PROBE_FILE" 2>/dev/null || true)
rm -f "$PROBE_FILE"
if echo "$BIOME_OUT" | grep -q "useExhaustiveDependencies"; then
  ok "Biome useExhaustiveDependencies fires correctly"
else
  warn "useExhaustiveDependencies did NOT fire on probe — check biome.json rule group"
fi

# ─── 7. Playwright ───────────────────────────────────────────────────────────
if ! $NODE_CMD -e "require('@playwright/test')" 2>/dev/null; then
  log "Installing Playwright..."
  npm install --save-dev @playwright/test 2>&1 | tail -3
  ok "Playwright installed"
else
  ok "Playwright already installed"
fi

# Install Chromium browser only
log "Installing Chromium browser..."
npx playwright install chromium 2>&1 | tail -5
ok "Chromium ready"

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
  "generate-import-report.mjs"
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
IMPORT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u)"
$NODE_CMD - <<HARNESS_JS
const fs = require('fs')
const data = {
  sourceGenerator: 'lovable',
  importDate: '${IMPORT_DATE}',
  harnessVersion: '${HARNESS_VERSION}',
  targetPath: '${TARGET}'
}
fs.writeFileSync('harness.json', JSON.stringify(data, null, 2) + '\n')
console.log('[import] harness.json written')
HARNESS_JS
ok "harness.json written"

# ─── 10. Import report ───────────────────────────────────────────────────────
log "Generating import-report.md..."
$NODE_CMD scripts/generate-import-report.mjs "$HARNESS_VERSION" 2>&1
ok "import-report.md generated"

# ─── 11. Commit harness additions ────────────────────────────────────────────
git add -A
if git diff --cached --quiet; then
  ok "Nothing new to commit (idempotent re-run)"
else
  git commit -m "chore: harness onboarding via import-lovable.sh (v${HARNESS_VERSION})"
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
