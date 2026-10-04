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
#      is not loopback, any URL whose host is built at runtime, any
#      protocol-relative URL, any raw network API or network command, and any
#      request call not aimed at loopback. Manifests (JSON/YAML/TOML) get the
#      URL scan too, since a harness reads them (an MCP server "url", say).
#      Pattern scans cannot prove absence; they catch the plain ways out. Read
#      every hit the guard reports, and read new code from upstream anyway.
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
  tests/no-egress/test-guard-self.sh
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
allow .codex-plugin/plugin.json '"url": "https://github.com/obra"' \
  "the author's profile link in the author block; display metadata, never fetched"
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

LOCAL='target is local'
allow skills/brainstorming/scripts/helper.js "return 'ws://' + window.location.host" \
  "$LOCAL: the page's own origin, which is the loopback companion"
allow skills/brainstorming/scripts/helper.js 'ws = new WebSocket(websocketUrl());' \
  "$LOCAL: websocketUrl() is the page's own origin"
allow skills/brainstorming/scripts/server.cjs "return 'http://' + URL_HOST + ':' + PORT" \
  "$LOCAL: URL_HOST is the constant 'localhost'; this builds the URL shown to the user"
allow skills/brainstorming/scripts/server.cjs "return origin === 'http://' + host;" \
  'a string comparison for the WebSocket origin check; no request'
allow tests/brainstorm-server/auth.test.js 'http.get(url, { headers }' "$LOCAL: url is http://localhost:TEST_PORT"
allow tests/brainstorm-server/auth.test.js 'const ws = new WebSocket(url, opts);' "$LOCAL: url is ws://localhost:TEST_PORT"
allow tests/brainstorm-server/server.test.js 'async function fetch(url) {' 'a local helper named fetch; its callers pass localhost URLs'
allow tests/brainstorm-server/server.test.js 'http.get(url, { headers }' "$LOCAL: the fetch helper above, called with localhost URLs"
allow tests/brainstorm-server/helper.test.js "const OFF_ORIGIN = 'https://evil.example';" \
  'test data for the link-blocking tests; handed to a fake DOM that only compares origins, never requested'
allow tests/brainstorm-server/helper.test.js "{ href: 'http://localhost:7777@evil.example/' }" \
  'test data: a userinfo URL the link blocker must refuse; handed to a fake DOM, never requested'
allow tests/brainstorm-server/lifecycle.test.js "require('http').get(lines[0]" \
  "$LOCAL: lines[0] is the URL the companion printed, always http://localhost"

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
# and allowlist bookkeeping survive. Every grep feeding it passes -H: over a
# single file grep would drop the path, and the allowlist could not match.
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

# In a git checkout: tracked files plus new ones not yet added (minus ignored
# ones), so a change is checked before `git add`; files deleted from the work
# tree are dropped. Anywhere else (an installed copy of the plugin has no .git)
# every file under the root, so the guard scans what a harness actually loads
# instead of passing on an empty list.
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] && [ -z "$(git rev-parse --show-prefix 2>/dev/null)" ]; then
  list_files() {
    git ls-files --cached --others --exclude-standard | sort -u |
      while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done
  }
else
  list_files() { find . -type f -not -path './.git/*' -not -path '*/node_modules/*' | sed 's|^\./||' | sort; }
fi

# read_lines NAME — fill array NAME from stdin, one element per line. mapfile
# needs bash 4; macOS still ships bash 3.2.
read_lines() {
  local _line
  eval "$1=()"
  while IFS= read -r _line; do eval "$1+=(\"\$_line\")"; done
}

# SVG and CSS count as code: a harness renders them (the Codex icon is an SVG)
# and both can name remote resources.
read_lines CODE_FILES < <(list_files | grep -E '\.(cjs|js|mjs|ts|py|sh|ps1|html|cmd|svg|css)$|^hooks/|^skills/[^/]+/scripts/' | grep -v 'package-lock\.json$')
read_lines MANIFESTS < <(list_files | grep -E '\.(json|ya?ml|toml)$' | grep -v 'package-lock\.json$')
read_lines SKILL_MD < <(list_files | grep -E '^skills/.*\.md$')
# History and licence texts are exempt: they describe upstream, not this fork.
read_lines TREE < <(list_files | grep -vE '^(RELEASE-NOTES\.md|CODE_OF_CONDUCT\.md|LICENSE|docs/superpowers/|docs/plans/)' | grep -v 'package-lock\.json$')

# A scan over no files passes without looking at anything. Refuse instead.
if [ "${#CODE_FILES[@]}" -eq 0 ] || [ "${#MANIFESTS[@]}" -eq 0 ] || [ "${#SKILL_MD[@]}" -eq 0 ] || [ "${#TREE[@]}" -eq 0 ]; then
  fail "found files to scan (code: ${#CODE_FILES[@]}, manifests: ${#MANIFESTS[@]}, skill markdown: ${#SKILL_MD[@]}, tree: ${#TREE[@]}) under $REPO_ROOT"
  echo
  echo "Passed: $PASSES  Failed: $FAILURES"
  exit 1
fi

# --- 1. code --------------------------------------------------------------
# URLs whose host is not loopback. The host is what follows the last @: in
# http://localhost@evil.com the request goes to evil.com. The character class
# leaves out , ; & + = ! on purpose: with them, 'http://localhost:3000,https://evil.com'
# matched as one loopback URL and swallowed the scheme of the second. Userinfo
# that needs those characters is caught by the userinfo check below instead.
LOCAL_HOST='^(localhost|127\.0\.0\.1|\[::1\])$'
# Schemes match in any case (grep -i below): browsers, Node and Python all
# fetch HTTPS://host the same as https://host.
URL_RE='(https?|wss?)://[][A-Za-z0-9._~%:@-]*[]A-Za-z0-9]'
# An XML namespace declaration (xmlns="http://www.w3.org/2000/svg") names a
# vocabulary; no parser or browser fetches it. Matched together with the URL
# so it can be skipped; any other URL in the same file is still checked.
NS_ATTR="xmlns(:[A-Za-z0-9._-]+)?=[\"']"
# Manifest fields that only describe the project; no harness fetches them.
META_KEY='"(homepage|repository|websiteURL|privacyPolicyURL|termsOfServiceURL)"[[:space:]]*:'
# non_loopback_urls FILE... — "path:line:source line" for each URL whose host
# is not loopback.
non_loopback_urls() {
  local hit path rest lineno url authority host
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    path="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; url="${rest#*:}"
    case "$url" in xmlns*) continue ;; esac
    authority="${url#*://}"; host="${authority##*@}"
    if [[ "$host" == \[* ]]; then host="${host%%]*}]"; else host="${host%%:*}"; fi
    host=$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')
    [[ "$host" =~ $LOCAL_HOST ]] && continue
    printf '%s:%s:%s\n' "$path" "$lineno" "$(sed -n "${lineno}p" "$path")"
  done < <(grep -HnoiE "($NS_ATTR)?$URL_RE" "$@" 2>/dev/null)
}
report "code: no URL to a non-loopback host" "$(non_loopback_urls "${CODE_FILES[@]}")"
report "manifests: no URL to a non-loopback host outside project metadata" \
  "$(non_loopback_urls "${MANIFESTS[@]}" | grep -vE "^[^:]*:[0-9]+:[[:space:]]*$META_KEY")"

# URLs with userinfo (user@host). A loopback name before the @ hides the real
# host, and http://localhost;x@evil.com stops the URL scan above at the ;.
# Nothing in this plugin needs credentials in a URL, so every one is a hit.
report "code and manifests: no URL with userinfo" \
  "$(grep -HniE "(https?|wss?)://[^/?#[:space:]\"'\`]*@" "${CODE_FILES[@]}" "${MANIFESTS[@]}" 2>/dev/null)"

# Protocol-relative URLs (//host/...) take the page's scheme, so they reach
# any host without naming one. Only in an attribute, a CSS url(), or at the
# start of a string literal; a // comment has a space or sits outside quotes.
report "code: no protocol-relative URL" \
  "$(grep -HnE "(src|href|action|poster|srcset|data)[[:space:]]*=[[:space:]]*[\"']?//[^/[:space:]]|url\([[:space:]]*[\"']?//[^/[:space:]]|[\"'\`]//[A-Za-z0-9-]+\.[A-Za-z0-9.-]+" "${CODE_FILES[@]}" 2>/dev/null)"

# URLs built at runtime: a scheme literal followed by a quote or `${`, so the
# host comes from a variable or a concatenation and the scan above cannot see
# it. Each one must be allowlisted with the reason its host is local.
report "code: no URL with a runtime-built host" \
  "$(grep -HniE "(https?|wss?)://['\"\`]|(https?|wss?)://\\$\\{" "${CODE_FILES[@]}" 2>/dev/null)"

# Modules and commands that only exist to reach another host.
# dns is here too: a lookup of <data>.attacker.example carries <data> out.
NET_API="require\\(['\"](node:)?(https|http2|net|dgram|tls|dns)(/promises)?['\"]\\)|from ['\"](node:)?(https?|http2|net|dgram|tls|dns)(/promises)?['\"]|XMLHttpRequest|sendBeacon|navigator\\.|urllib|http\\.client|requests\\.(get|post|put|patch|delete|head|request|Session)\\(|httpx|aiohttp|socket\\.(socket|create_connection|gethostbyname|getaddrinfo)|asyncio\\.open_connection|dnspython|import dns"
# Package managers are listed one by one: every install downloads, and an
# install command printed for the agent is an instruction like any other.
NET_CMD='curl |curl\.exe|wget |\biwr |\birm |gh (issue|api|pr|repo|search|gist|release|run|workflow|auth|browse|secret)|git (push|fetch|pull|clone|ls-remote|remote update|submodule update)|npm (install|ci|i)([^a-z]|$)|npx |pip3? install|pipx install|uv (pip|sync|add|tool)|yarn (install|add)|pnpm (install|add|i)([^a-z]|$)|bun (install|add)|gem install|bundle install|composer (install|require)|brew (install|upgrade|update)|apt(-get)? (install|update|upgrade)|winget install|choco install|scoop install|certutil.*-urlcache|bitsadmin|/dev/(tcp|udp)/|\bnc |\bncat |Invoke-(WebRequest|RestMethod)|Net\.WebClient|Start-BitsTransfer'
report "code: no raw network API or network command" \
  "$(grep -HnE "$NET_API|$NET_CMD" "${CODE_FILES[@]}" 2>/dev/null)"

# Request calls. A call is fine when its line names a loopback host; any other
# call must be allowlisted with the reason its target is local. The host must
# end there: localhost@evil.com and localhost.evil.com are not loopback.
NET_CALL="(^|[^A-Za-z0-9_.])fetch\\(|new WebSocket\\(|EventSource\\(|\\bhttps?\\.(get|request)\\(|require\\(['\"](node:)?https?['\"]\\)\\.(get|request)\\("
LOOPBACK_ON_LINE="[\"'\`/](localhost|127\\.0\\.0\\.1|\\[::1\\])([^@A-Za-z0-9._~%-]|$)"
report "code: every request call targets loopback" \
  "$(grep -HnE "$NET_CALL" "${CODE_FILES[@]}" 2>/dev/null | grep -vE "$LOOPBACK_ON_LINE")"

# --- 2. skill markdown ----------------------------------------------------
AUTOLOAD='<img[^>]*src=.?https?:|<(script|link|iframe|video|audio|source)[^>]*(src|href)=.?https?:|@import|url\(.?https?:|!\[[^]]*\]\(https?:'
report "skills: no auto-loaded remote resource" \
  "$(grep -HnE -i "$AUTOLOAD" "${SKILL_MD[@]}" 2>/dev/null)"

MD_CMD="$NET_CMD"'|api\.github\.com|poetry install|cargo (build|install)|go mod download|go get '
report "skills: every network command is allowlisted as gated" \
  "$(grep -HnE -i "$MD_CMD" "${SKILL_MD[@]}" 2>/dev/null)"

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
REMOVED='primeradiant|mintcdn|unsplash|BRAINSTORM_OPEN_CMD|BRAINSTORM_(URL_)?HOST|SUPERPOWERS_BRAND_IMAGE_URL|TELEMETRY_DISABLE_ENV_VARS|0\.0\.0\.0|diagnosing-superpowers|openai-codex-plugins|dangerously-skip-permissions|bypassPermissions'
report "tree: removed telemetry, remote binds, upstream reporting and permission bypasses stay out" \
  "$(grep -Hn -i -E "$REMOVED" "${TREE[@]}" 2>/dev/null)"
# The same names in file paths: a restored skill directory can come back
# without its name appearing in any file's content.
report "tree: no file path names a removed component" \
  "$(printf '%s\n' "${TREE[@]}" | grep -i -E "$REMOVED" | sed 's/.*/&:0:(file path)/')"

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
