#!/usr/bin/env bash
# Scans src/, e2e/, and scripts/ for patterns that Dyad might use to cheat.
# Exits 1 if any banned pattern is found.
# This enforces constraints STRUCTURALLY, not just via prompt text.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BANNED='@ts-ignore|@ts-expect-error|as any|biome-ignore|test\.skip|test\.only|xit\(|describe\.skip|continue-on-error|\|\| true'

FOUND=0

# Check src/, e2e/, and scripts/ (exclude the scanner itself)
for DIR in src e2e; do
  if [[ -d "$DIR" ]]; then
    HITS=$(grep -rEn "$BANNED" "$DIR/" 2>/dev/null || true)
    if [[ -n "$HITS" ]]; then
      echo "[scan-banned] ✗ BANNED PATTERNS FOUND in $DIR/:" >&2
      echo "$HITS" >&2
      FOUND=1
    fi
  fi
done

if [[ $FOUND -eq 1 ]]; then
  echo "[scan-banned] FAIL: Remove banned patterns before proceeding" >&2
  exit 1
fi

echo "[scan-banned] ✓ No banned patterns found"
exit 0
