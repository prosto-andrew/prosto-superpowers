#!/usr/bin/env bash
# Tests for the no-egress guard itself: copy it into a throwaway repository
# seeded with paths out it must report, plus look-alikes it must leave alone,
# and check what it flags.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/test-no-egress.sh"

FAILURES=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

repo="$TEST_ROOT/repo"
mkdir -p "$repo/tests/no-egress" "$repo/skills/demo/scripts" "$repo/assets"
cp "$GUARD" "$repo/tests/no-egress/test-no-egress.sh"
git init -q "$repo"

printf '{ "name": "demo" }\n' > "$repo/manifest.json"
printf -- '---\nname: demo\n---\n\nSet up with `yarn install`.\n' > "$repo/skills/demo/SKILL.md"
# A remote image with an upper-case scheme, which browsers fetch all the same.
printf '<img src="HTTPS://cdn.example/p.png">\n' > "$repo/skills/demo/scripts/page.html"
# An install command printed for the agent to run.
printf "console.error('  brew install graphviz');\n" > "$repo/skills/demo/scripts/hint.js"
# An SVG a harness renders, loading a remote image.
printf '<svg xmlns="http://www.w3.org/2000/svg"><image href="https://cdn.example/x.png"/></svg>\n' \
  > "$repo/assets/remote.svg"
# An SVG whose only URL is its namespace name, which is never fetched.
printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><path d="M0 0"/></svg>\n' \
  > "$repo/assets/clean.svg"

echo "=== Test: no-egress guard catches paths out ==="

# The fixture lacks the files the real allowlist names, so the guard also
# reports stale entries here; only the hits listed under a check matter.
out="$(cd "$repo" && bash tests/no-egress/test-no-egress.sh 2>&1)" || true

check_flagged() {
  local path="$1" label="$2"
  if printf '%s\n' "$out" | grep -q "^    $path:"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_flagged "skills/demo/scripts/page.html" "flags a URL with an upper-case scheme"
check_flagged "skills/demo/scripts/hint.js" "flags an install command from another package manager"
check_flagged "skills/demo/SKILL.md" "flags an ungated install command in skill markdown"
check_flagged "assets/remote.svg" "scans SVG files for remote URLs"

if printf '%s\n' "$out" | grep -q "^    assets/clean.svg:"; then
  fail "leaves XML namespace names alone"
else
  pass "leaves XML namespace names alone"
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo ""
  echo "Guard output:"
  printf '%s\n' "$out" | sed 's/^/    | /'
  echo "FAILED: $FAILURES assertion(s)."
  exit 1
fi
echo "PASS"
