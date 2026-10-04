#!/usr/bin/env bash
# Fast tests for start-server.sh shell-only platform decisions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
START_SCRIPT="$REPO_ROOT/skills/brainstorming/scripts/start-server.sh"
REAL_NODE="$(command -v node)"

TEST_DIR="${TMPDIR:-/tmp}/brainstorm-start-test-$$"
passed=0
failed=0

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
  echo "  PASS: $1"
  passed=$((passed + 1))
}

fail() {
  echo "  FAIL: $1"
  echo "    $2"
  failed=$((failed + 1))
}

make_fake_uname() {
  local fake_bin="$1"
  cat > "$fake_bin/uname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-s" ]]; then
  echo "MINGW64_NT-10.0"
else
  /usr/bin/uname "$@"
fi
EOF
  chmod +x "$fake_bin/uname"
}

echo ""
echo "--- start-server.sh platform detection ---"

mkdir -p "$TEST_DIR/fake-bin" "$TEST_DIR/project"
make_fake_uname "$TEST_DIR/fake-bin"

cat > "$TEST_DIR/fake-bin/node" <<'EOF'
#!/usr/bin/env bash
echo "CAPTURED_OWNER_PID=${BRAINSTORM_OWNER_PID:-__UNSET__}"
printf 'CAPTURED_ARGV=%s\n' "$@"
exit 0
EOF
chmod +x "$TEST_DIR/fake-bin/node"

captured=$(
  PATH="$TEST_DIR/fake-bin:$PATH" \
    MSYSTEM="" \
    bash "$START_SCRIPT" --project-dir "$TEST_DIR/project" --foreground 2>/dev/null || true
)
owner_pid_value=$(echo "$captured" | grep "CAPTURED_OWNER_PID=" | head -1 | sed 's/CAPTURED_OWNER_PID=//')

if [[ "$owner_pid_value" == "" || "$owner_pid_value" == "__UNSET__" ]]; then
  pass "clears BRAINSTORM_OWNER_PID when uname reports a Windows-like shell"
else
  fail "clears BRAINSTORM_OWNER_PID when uname reports a Windows-like shell" \
       "expected empty or unset, got '$owner_pid_value'"
fi

if echo "$captured" | grep -Eq '^CAPTURED_ARGV=--brainstorm-server-id=[A-Za-z0-9_-]{32,64}$'; then
  pass "passes shell-safe server instance id argv"
else
  fail "passes shell-safe server instance id argv" \
       "expected exact --brainstorm-server-id=<safe id> argv line, got: $captured"
fi

server_id_file=$(find "$TEST_DIR/project/.superpowers/brainstorm" -name server-instance-id -print 2>/dev/null | head -1)
server_id_value=""
if [[ -n "$server_id_file" ]]; then
  server_id_value="$(tr -d '\r\n' < "$server_id_file")"
fi
if [[ "$server_id_value" =~ ^[A-Za-z0-9_-]{32,64}$ ]]; then
  pass "writes shell-safe server-instance-id state file"
else
  fail "writes shell-safe server-instance-id state file" \
       "expected valid id in state, got '$server_id_value'"
fi

rm -rf "$TEST_DIR/project"/*

cat > "$TEST_DIR/fake-bin/node" <<'EOF'
#!/usr/bin/env bash
echo "FOREGROUND_MODE=true"
exit 0
EOF
chmod +x "$TEST_DIR/fake-bin/node"

captured=$(
  PATH="$TEST_DIR/fake-bin:$PATH" \
    MSYSTEM="" \
    bash "$START_SCRIPT" --project-dir "$TEST_DIR/project" 2>/dev/null || true
)

if echo "$captured" | grep -q "FOREGROUND_MODE=true"; then
  pass "auto-foregrounds when uname reports a Windows-like shell"
else
  fail "auto-foregrounds when uname reports a Windows-like shell" \
       "expected foreground node path, got: $captured"
fi

echo ""
echo "--- start-server.sh errors are valid JSON ---"

# The agent parses what start-server.sh prints; a raw path or argument with a
# backslash (any Windows path) or a quote must not break the JSON.
is_json() { "$REAL_NODE" -e 'JSON.parse(require("fs").readFileSync(0, "utf8"))' <<< "$1" >/dev/null 2>&1; }

bad_arg_out=$(bash "$START_SCRIPT" 'C:\new "dir"' 2>/dev/null || true)
if is_json "$bad_arg_out"; then
  pass "unknown-argument error is valid JSON"
else
  fail "unknown-argument error is valid JSON" "got: $bad_arg_out"
fi

# A server that reports started and dies at once takes the "killed" path.
cat > "$TEST_DIR/fake-bin/node" <<'EOF'
#!/usr/bin/env bash
echo '{"type":"server-started"}'
exit 0
EOF
chmod +x "$TEST_DIR/fake-bin/node"
if command -v cygpath >/dev/null 2>&1; then
  killed_project="$(cygpath -w "$TEST_DIR/killed")"
else
  killed_project="$TEST_DIR/killed \"quoted\" dir"
fi
killed_out=$(
  PATH="$TEST_DIR/fake-bin:$PATH" MSYSTEM="" \
    bash "$START_SCRIPT" --project-dir "$killed_project" --background 2>/dev/null || true
)
if [[ "$killed_out" == *"Server started but was killed"* ]] && is_json "$killed_out"; then
  pass "server-killed error with the project path is valid JSON"
else
  fail "server-killed error with the project path is valid JSON" "got: $killed_out"
fi

echo ""
echo "--- start-server.sh session files stay out of git ---"

# Session files hold the session key, the user's choices and absolute paths;
# a project without a .superpowers/ ignore rule must not pick them up.
git init -q "$TEST_DIR/gitproject"
PATH="$TEST_DIR/fake-bin:$PATH" MSYSTEM="" \
  bash "$START_SCRIPT" --project-dir "$TEST_DIR/gitproject" --foreground >/dev/null 2>&1 || true

status=$(git -C "$TEST_DIR/gitproject" status --porcelain --untracked-files=all)
if [[ -d "$TEST_DIR/gitproject/.superpowers/brainstorm" && "$status" != *".superpowers"* ]]; then
  pass "brainstorm session dir is invisible to git status"
else
  fail "brainstorm session dir is invisible to git status" "status: $status"
fi

git -C "$TEST_DIR/gitproject" add -A
staged=$(git -C "$TEST_DIR/gitproject" diff --cached --name-only)
if [[ "$staged" != *".superpowers"* ]]; then
  pass "git add -A does not stage brainstorm session files"
else
  fail "git add -A does not stage brainstorm session files" "staged: $staged"
fi

echo ""
echo "--- Results: $passed passed, $failed failed ---"
if [[ $failed -gt 0 ]]; then
  exit 1
fi
