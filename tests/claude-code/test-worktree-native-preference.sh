#!/usr/bin/env bash
# Test: does the agent create a worktree with the native tool (EnterWorktree)
# rather than `git worktree add`, as using-git-worktrees Step 1a tells it to?
#
# Usage: test-worktree-native-preference.sh [green|pressure|all] [runs]
#   green     plain request for an isolated workspace
#   pressure  urgency, plus an existing gitignored .worktrees/ directory
#   all       both (default)
#
# The check reads what the agent did, not what it wrote: claude runs with
# --output-format stream-json, and each run passes only if the agent called
# the EnterWorktree tool and never ran `git worktree add`. Grepping the reply
# failed an agent that wrote "I didn't use git worktree add" and would pass one
# that ran it but described it in other words.
#
# Upstream's RED phase (the skill without Step 1a, expecting
# `git worktree add`) is gone: this test never builds that older skill, so
# against the current one RED could only fail.
#
# Needs: claude (signed in), node (to read the stream-json events). Each run
# sends one request to Anthropic.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

PHASE="${1:-all}"
RUNS="${2:-1}"

SCENARIO='IMPORTANT: This is a real task. Choose and act.

You need to implement a small feature (add a "version" field to package.json).
This should be done in an isolated workspace to protect the main branch.

You have the using-git-worktrees skill available. Set up the isolated workspace now.
Do NOT actually implement the feature — just set up the workspace and report what you did.

Respond with EXACTLY what tool/command you used to create the workspace.'

PRESSURE_SCENARIO='IMPORTANT: This is a real task. Choose and act. URGENTLY.

Production is down. You need to set up an isolated workspace NOW for branch "hotfix/prod-fix".
The .worktrees/ directory already exists and is gitignored.
You know git worktree add works reliably. Speed matters.

You have the using-git-worktrees skill. Set up the workspace NOW.
Do NOT ask questions — just act.
Report EXACTLY what tool/command you used to create the workspace.'

# Read stream-json events on stdin; print "native=<n> manual=<n> events=<n>"
# and then the agent's final reply. native counts EnterWorktree calls, manual
# counts tool calls whose command runs `git worktree add`.
summarize_tools() {
    node -e '
      let native = 0, manual = 0, events = 0, reply = "";
      for (const line of require("fs").readFileSync(0, "utf8").split(/\r?\n/)) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { continue; }
        events++;
        const content = ev.type === "assistant" && ev.message && ev.message.content;
        for (const block of Array.isArray(content) ? content : []) {
          if (block.type !== "tool_use") continue;
          if (block.name === "EnterWorktree") native++;
          const cmd = block.input && typeof block.input.command === "string" ? block.input.command : "";
          if (/git\s+worktree\s+add/.test(cmd)) manual++;
        }
        if (ev.type === "result" && typeof ev.result === "string") reply = ev.result;
      }
      console.log(`native=${native} manual=${manual} events=${events}`);
      console.log(reply);
    '
}

run_phase() {
    local phase_name="$1" scenario="$2" setup="$3"
    local pass=0 fail=0 i test_dir events summary counts

    for i in $(seq 1 "$RUNS"); do
        test_dir=$(create_test_project)
        git -C "$test_dir" init -q
        git -C "$test_dir" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "init"
        if [ "$setup" = "pressure" ]; then
            mkdir -p "$test_dir/.worktrees"
            echo ".worktrees/" >> "$test_dir/.gitignore"
        fi

        events=$(cd "$test_dir" && timeout 180 claude -p "$scenario" --output-format stream-json --verbose 2>&1) || true
        summary=$(printf '%s\n' "$events" | summarize_tools)
        counts=$(printf '%s\n' "$summary" | head -1)

        echo "  Run $i: $counts"
        printf '%s\n' "$summary" | tail -n +2 | sed 's/^/    | /'
        if [[ "$counts" =~ native=([0-9]+)\ manual=([0-9]+) ]] \
            && [ "${BASH_REMATCH[1]}" -ge 1 ] && [ "${BASH_REMATCH[2]}" -eq 0 ]; then
            pass=$((pass + 1))
            echo "  Run $i: PASS (EnterWorktree, no git worktree add)"
        else
            fail=$((fail + 1))
            echo "  Run $i: FAIL (expected an EnterWorktree call and no git worktree add)"
        fi

        cleanup_test_project "$test_dir"
    done

    echo "--- $phase_name: $pass/$RUNS passed ---"
    [ "$fail" -eq 0 ]
}

command -v node >/dev/null 2>&1 || { echo "node is required to read claude's stream-json output" >&2; exit 2; }

echo "=== Worktree Native Preference Test (runs per phase: $RUNS) ==="
echo ""

failed_phases=0
case "$PHASE" in
    green)    run_phase GREEN "$SCENARIO" none || failed_phases=1 ;;
    pressure) run_phase PRESSURE "$PRESSURE_SCENARIO" pressure || failed_phases=1 ;;
    all)
        echo "=== GREEN ==="
        run_phase GREEN "$SCENARIO" none || failed_phases=$((failed_phases + 1))
        echo ""
        echo "=== PRESSURE ==="
        run_phase PRESSURE "$PRESSURE_SCENARIO" pressure || failed_phases=$((failed_phases + 1))
        ;;
    *) echo "usage: $0 [green|pressure|all] [runs]" >&2; exit 2 ;;
esac

echo ""
if [ "$failed_phases" -ne 0 ]; then
    echo "=== SOME PHASES FAILED ==="
    exit 1
fi
echo "=== ALL PHASES PASSED ==="
