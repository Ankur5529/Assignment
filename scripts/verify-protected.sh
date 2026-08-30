#!/usr/bin/env bash
# Verifies that no files under e2e/, scripts/, biome.json, tsconfig.json,
# or playwright.config.* have been modified since the last green commit.
#
# Run AFTER every Dyad invocation, BEFORE re-gating.
# Either failure here → immediate escalation, NOT another retry attempt.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROTECTED=(
  "e2e/"
  "scripts/"
  "biome.json"
  "tsconfig.json"
  "tsconfig.node.json"
  "playwright.config.ts"
  "playwright.config.js"
)

# Find the last green commit tag or HEAD~1
GREEN_REF="${HARNESS_GREEN_COMMIT:-HEAD~1}"

VIOLATIONS=0

for P in "${PROTECTED[@]}"; do
  # Check if path exists in the tree
  if [[ ! -e "$P" ]] && [[ ! -d "$P" ]]; then
    continue
  fi

  # Compare against the green reference
  if git diff --name-only "$GREEN_REF" HEAD -- "$P" 2>/dev/null | grep -q .; then
    echo "[verify-protected] ✗ PROTECTED PATH MODIFIED: $P" >&2
    git diff --name-only "$GREEN_REF" HEAD -- "$P" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi

  # Also check working tree (uncommitted changes)
  if git status --short -- "$P" 2>/dev/null | grep -qE "^[MADRCU?]"; then
    echo "[verify-protected] ✗ UNCOMMITTED CHANGE in protected path: $P" >&2
    git status --short -- "$P" >&2
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
done

if [[ $VIOLATIONS -gt 0 ]]; then
  echo "[verify-protected] FAIL: $VIOLATIONS protected-path violation(s)" >&2
  echo "[verify-protected] Dyad must not touch e2e/, scripts/, or gate configs" >&2
  exit 1
fi

echo "[verify-protected] ✓ All protected paths intact"
exit 0
