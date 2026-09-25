#!/usr/bin/env bash
# No-egress guard for superpowers-custom.
#
# This fork's promise: nothing in the plugin sends data off the machine on its
# own, and every network command a skill tells the agent to run sits behind the
# "Network commands need their own yes" rule. Run this after every merge from
# upstream; a new hit means upstream added a path out, and it must be removed
# or consciously allowlisted below with a reason.
#
# Three scans:
#   1. Code (scripts, hooks, JS/TS/Python, HTML, tests): any URL to a host that
#      is not loopback, and any raw network API or network command.
#   2. Skill markdown: auto-loaded remote resources, and network commands.
#   3. Whole tree: names of the specific things this fork removed.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 2

PASSES=0
FAILURES=0
pass() { echo "  [PASS] $1"; PASSES=$((PASSES + 1)); }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# Files that carry these patterns as data: the guards themselves.
SELF_EXCLUDES=(
  tests/no-egress/test-no-egress.sh
  tests/diagnosing-sessions/test-skill-structure.sh
)

# Allowlist: path, a fixed substring of the matching line, and why it is fine.
ALLOW_PATH=()
ALLOW_TEXT=()
ALLOW_WHY=()
allow() { ALLOW_PATH+=("$1"); ALLOW_TEXT+=("$2"); ALLOW_WHY+=("$3"); }

GATE='Network commands need their own yes'
GATED='gated by the rule in this file'

allow hooks/session-start 'See: https://github.com/obra/superpowers/issues/571' \
  'comment citing the upstream bug behind the printf workaround; never fetched'
allow tests/claude-code/run-skill-tests.sh 'Install Claude Code first: https://code.claude.com' \
  'text printed when claude is missing; never fetched'
allow skills/finishing-a-development-branch/SKILL.md "$GATE" 'the gate rule itself names the commands it gates'
allow skills/finishing-a-development-branch/SKILL.md 'git pull   # network: ask first' "$GATED"
allow skills/finishing-a-development-branch/SKILL.md 'git push -u origin <feature-branch>' "$GATED"
allow skills/finishing-a-development-branch/SKILL.md '# git push origin HEAD:refs/heads/<new-branch>' "$GATED"
allow skills/receiving-code-review/SKILL.md "$GATE" 'the gate rule itself names the commands it gates'
allow skills/receiving-code-review/SKILL.md 'gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies' "$GATED"
allow skills/using-git-worktrees/SKILL.md "$GATE" 'the gate rule itself names the commands it gates'
allow skills/using-git-worktrees/SKILL.md 'then npm install; fi' "$GATED"
allow skills/using-git-worktrees/SKILL.md 'then cargo build; fi' "$GATED"
allow skills/using-git-worktrees/SKILL.md 'then pip install -r requirements.txt; fi' "$GATED"
allow skills/using-git-worktrees/SKILL.md 'then poetry install; fi' "$GATED"
allow skills/using-git-worktrees/SKILL.md 'then go mod download; fi' "$GATED"
allow skills/writing-skills/anthropic-best-practices.md 'Install required package: `pip install pypdf`' \
  'example sentence inside a guide on writing skills; not an instruction to this agent'

ALLOW_USED=()
for _ in "${ALLOW_PATH[@]}"; do ALLOW_USED+=(0); done

is_allowed() {
  local path="$1" content="$2" i
  for i in "${!ALLOW_PATH[@]}"; do
    if [[ "$path" == "${ALLOW_PATH[$i]}" && "$content" == *"${ALLOW_TEXT[$i]}"* ]]; then
      ALLOW_USED[$i]=1
      return 0
    fi
  done
  return 1
}

is_self() {
  local f
  for f in "${SELF_EXCLUDES[@]}"; do [[ "$1" == "$f" ]] && return 0; done
  return 1
}

# report NAME HITS — HITS is newline-separated "path:line:content". Takes its
# input as an argument, not stdin, so it runs in this shell and the counters
# and allowlist bookkeeping survive.
report() {
  local name="$1" hits="" line path rest content
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line%%:*}"; rest="${line#*:}"; content="${rest#*:}"
    is_self "$path" && continue
    is_allowed "$path" "$content" && continue
    hits+="$line"$'\n'
  done <<< "$2"
  if [ -z "$hits" ]; then
    pass "$name"
  else
    fail "$name"
    printf '%s' "$hits" | head -20 | cut -c1-200 | sed 's/^/    /'
  fi
}

echo "no-egress guard"

# --- 1. code --------------------------------------------------------------
mapfile -t CODE_FILES < <(git ls-files | grep -E '\.(cjs|js|mjs|ts|py|sh|html|cmd)$|^hooks/|^skills/[^/]+/scripts/' | grep -v 'package-lock\.json$')

# URLs whose host is not loopback. `'http://' + host` builds a local URL and
# carries no literal host, so it does not match.
LOCAL_HOST='^(localhost|127\.0\.0\.1|\[::1\])$'
url_hits=""
while IFS= read -r hit; do
  [ -z "$hit" ] && continue
  path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; url="${rest#*:}"
  host="${url#*://}"; host="${host%%[:/]*}"
  [[ "$host" =~ $LOCAL_HOST ]] && continue
  url_hits+="$path:$lineno:$(sed -n "${lineno}p" "$path")"$'\n'
done < <(grep -noE '(https?|wss?)://[][A-Za-z0-9.:-]*[A-Za-z0-9]' "${CODE_FILES[@]}" 2>/dev/null)
report "code: no URL to a non-loopback host" "$url_hits"

NET_API="require\\(['\"](https|net|dgram|tls)['\"]\\)|XMLHttpRequest|sendBeacon|navigator\\.|urllib|http\\.client|requests\\.(get|post)|socket\\.socket"
NET_CMD='curl |wget |gh (issue|api|pr|repo|search|gist)|git (push|fetch|pull|clone)|npm (install|ci|i)([^a-z]|$)|npx |pip install'
report "code: no raw network API or network command" \
  "$(grep -nE "$NET_API|$NET_CMD" "${CODE_FILES[@]}" 2>/dev/null)"

# --- 2. skill markdown ----------------------------------------------------
mapfile -t SKILL_MD < <(git ls-files 'skills/*.md' 'skills/**/*.md' | sort -u)

AUTOLOAD='<img[^>]*src=.?https?:|<(script|link|iframe|video|audio|source)[^>]*(src|href)=.?https?:|@import|url\(.?https?:|!\[[^]]*\]\(https?:'
report "skills: no auto-loaded remote resource" \
  "$(grep -nE -i "$AUTOLOAD" "${SKILL_MD[@]}" 2>/dev/null)"

MD_CMD="$NET_CMD"'|api\.github\.com|poetry install|cargo (build|install)|go mod download|go get '
report "skills: every network command is allowlisted as gated" \
  "$(grep -nE -i "$MD_CMD" "${SKILL_MD[@]}" 2>/dev/null)"

# The allowlist is only honest if the gate is really there.
gate_ok=1
for i in "${!ALLOW_PATH[@]}"; do
  [ "${ALLOW_WHY[$i]}" == "$GATED" ] || continue
  if ! grep -qF "$GATE" "${ALLOW_PATH[$i]}"; then
    fail "gate rule present in ${ALLOW_PATH[$i]}"
    gate_ok=0
  fi
done
[ "$gate_ok" -eq 1 ] && pass "every file with a gated command carries the gate rule"

# --- 3. removed things stay removed --------------------------------------
# History and licence texts are exempt: they describe upstream, not this fork.
mapfile -t TREE < <(git ls-files | grep -vE '^(RELEASE-NOTES\.md|CODE_OF_CONDUCT\.md|LICENSE|docs/superpowers/|docs/plans/)' | grep -v 'package-lock\.json$')
REMOVED='primeradiant|mintcdn|unsplash|BRAINSTORM_OPEN_CMD|BRAINSTORM_(URL_)?HOST|SUPERPOWERS_BRAND_IMAGE_URL|TELEMETRY_DISABLE_ENV_VARS|0\.0\.0\.0|diagnosing-superpowers|openai-codex-plugins|dangerously-skip-permissions|bypassPermissions'
report "tree: removed telemetry, remote binds, upstream reporting and permission bypasses stay out" \
  "$(grep -n -i -E "$REMOVED" "${TREE[@]}" 2>/dev/null)"

# --- allowlist hygiene ----------------------------------------------------
# An entry that matches nothing is stale. The gate sentence is exempt: it only
# matches when it names a command, and its presence is checked above.
stale=""
for i in "${!ALLOW_PATH[@]}"; do
  [ "${ALLOW_USED[$i]}" -eq 1 ] && continue
  [ "${ALLOW_TEXT[$i]}" == "$GATE" ] && continue
  stale+="${ALLOW_PATH[$i]}: ${ALLOW_TEXT[$i]}"$'\n'
done
if [ -z "$stale" ]; then
  pass "no stale allowlist entries"
else
  fail "no stale allowlist entries (remove them or fix the text)"
  printf '%s' "$stale" | sed 's/^/    /'
fi

echo
echo "Passed: $PASSES  Failed: $FAILURES"
[ "$FAILURES" -eq 0 ]
