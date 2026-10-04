#!/usr/bin/env bash
# Test: subagent-driven-development skill
# Asks a fresh agent questions only the loaded skill answers, and checks each
# answer against what the skill says.
#
# Every question demands a fixed answer shape with closed choices, and each
# expected value comes from the skill text (cited beside it), not from a
# model's earlier answer. Free-text keyword matching passed wrong answers
# ("start" in "reread at the start of each task") and failed right ones
# ("during Setup"); a closed choice does neither. One run is one sample:
# a failure says this answer contradicted the skill, not that the skill is
# broken; rerun before drawing conclusions.
#
# Behavior in a real SDD run (dispatch, review loops) is not covered here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

CLAUDE_PROMPT_TIMEOUT="${CLAUDE_PROMPT_TIMEOUT:-90}"
FAILURES=0

# check OUTPUT PATTERN NAME — record a failure but keep going, so one bad
# answer does not hide the rest of the run.
check() {
    assert_contains "$@" || FAILURES=$((FAILURES + 1))
}

ask() {
    run_claude "$1" "$CLAUDE_PROMPT_TIMEOUT" || true
}

echo "=== Test: subagent-driven-development skill ==="
echo ""

# Test 1: facts that exist only in the skill (SKILL.md: ledger at
# <workspace>/progress.md; `bash scripts/task-brief PLAN_FILE N`).
echo "Test 1: Skill is loaded..."
output=$(ask "In the subagent-driven-development skill, what is the progress ledger file called, and which script extracts one task's text for the implementer? Answer using exactly this structure:
Ledger file: <file name>
Task text script: <script name>")
check "$output" "Ledger file:[^a-z0-9]*progress\.md" "Names the ledger file progress.md"
check "$output" "Task text script:.*task-brief" "Names the task-brief script"
echo ""

# Test 2: one task reviewer per task, and its report needs both verdicts
# (SKILL.md "Review the task": "spec compliance AND task quality are both
# required").
echo "Test 2: Task review..."
output=$(ask "In subagent-driven-development, how many task reviewers review each finished task, and which verdicts must the review contain? Answer using exactly this structure:
Task reviewers per task: <number>
Verdicts required: <spec compliance only | task quality only | both spec compliance and task quality>")
check "$output" "Task reviewers per task:[^a-z0-9]*\(1\|one\)\b" "One task reviewer per task"
check "$output" "Verdicts required:[^a-z]*both" "Both verdicts required"
echo ""

# Test 3: implementers self-review, and it never replaces the task review
# (SKILL.md: "Implementer self-review never replaces the task review").
echo "Test 3: Self-review requirement..."
output=$(ask "Does the subagent-driven-development skill require implementers to self-review before handoff, and can self-review replace the task review? Answer using exactly this structure:
Self-review required: <yes or no>
Self-review replaces the task review: <yes or no>")
check "$output" "Self-review required:[^a-z]*yes\b" "Self-review is required"
check "$output" "Self-review replaces the task review:[^a-z]*no\b" "Self-review does not replace the task review"
echo ""

# Test 4: the controller reads the plan once, before Task 1 (SKILL.md: "Read
# the plan once ..."; "Before dispatching Task 1, scan the plan once").
echo "Test 4: Plan reading..."
output=$(ask "In subagent-driven-development, how many times does the controller read the whole plan file, and when? Answer using exactly this structure:
Times: <number>
When: <before dispatching Task 1 | before each task | after all tasks>")
check "$output" "Times:[^a-z0-9]*\(1\|one\|once\)[^a-z0-9]*$" "Reads the plan once"
check "$output" "When:[^a-z]*before dispatching task 1" "Reads it before dispatching Task 1"
echo ""

# Test 5: the reviewer treats the report as unverified claims and checks them
# against the diff (task-reviewer-prompt.md "Do Not Trust the Report").
echo "Test 5: Reviewer and the implementer's report..."
output=$(ask "In subagent-driven-development, how does the task reviewer treat the implementer's report? Answer using exactly this structure:
Trusts the report as accurate: <yes or no>
Verifies the report's claims against: <the report itself | the diff>")
check "$output" "Trusts the report as accurate:[^a-z]*no\b" "Does not trust the report"
check "$output" "Verifies the report's claims against:[^a-z]*the diff" "Checks claims against the diff"
echo ""

# Test 6: findings go back to an implementer, each fix gets a scoped re-review,
# five rounds at most (SKILL.md: "A fix round is one fix dispatch plus one
# scoped re-review. Five rounds maximum per task"; "Never fix findings
# yourself in the controller session").
echo "Test 6: Fix loop..."
output=$(ask "In subagent-driven-development, what happens when the task reviewer finds issues? Answer using exactly this structure:
Who fixes the findings: <the controller | the reviewer | an implementer>
Review after each fix: <none | a scoped re-review>
Maximum fix rounds per task: <number>")
check "$output" "Who fixes the findings:[^a-z]*\(an\|the\) implementer" "An implementer fixes the findings"
check "$output" "Review after each fix:[^a-z]*a scoped re-review" "Each fix gets a scoped re-review"
check "$output" "Maximum fix rounds per task:[^a-z0-9]*\(5\|five\)\b" "Five fix rounds at most"
echo ""

# Test 7: the task travels as a brief file; nobody reads the whole plan
# (SKILL.md "Task brief": run task-brief, give the implementer the brief path;
# "Never make a subagent read the whole plan file").
echo "Test 7: Task context provision..."
output=$(ask "In subagent-driven-development, how does the controller give the implementer its task? Answer using exactly this structure:
Task text delivered: <pasted into the prompt | as a brief file path>
Implementer reads the whole plan file: <yes or no>")
check "$output" "Task text delivered:[^a-z]*as a brief file" "Delivers the task as a brief file"
check "$output" "Implementer reads the whole plan file:[^a-z]*no\b" "Implementer does not read the whole plan"
echo ""

# Test 8: isolated workspace via using-git-worktrees (SKILL.md: "use
# superpowers:using-git-worktrees to create one or verify the existing one").
echo "Test 8: Workspace skill..."
output=$(ask "Which skill does subagent-driven-development use to set up an isolated workspace? Answer using exactly this structure:
Workspace skill: <skill name>")
check "$output" "Workspace skill:.*using-git-worktrees" "Names using-git-worktrees"
echo ""

# Test 9: no start on main without explicit consent (SKILL.md: "Never start
# implementation on a main/master branch without your human partner's
# explicit consent").
echo "Test 9: Main branch..."
output=$(ask "In subagent-driven-development, may implementation start directly on the main branch? Answer using exactly this structure:
Without explicit consent from your human partner: <yes or no>
With explicit consent from your human partner: <yes or no>")
check "$output" "Without explicit consent from your human partner:[^a-z]*no\b" "Not on main without consent"
check "$output" "With explicit consent from your human partner:[^a-z]*yes\b" "On main only with explicit consent"
echo ""

if [[ "$FAILURES" -ne 0 ]]; then
    echo "=== FAILED: $FAILURES check(s) ==="
    exit 1
fi
echo "=== All subagent-driven-development skill tests passed ==="
