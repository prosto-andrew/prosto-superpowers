# Claude Code Skills Tests

Automated tests for superpowers skills using Claude Code CLI.

## Overview

This test suite verifies that skills are loaded correctly and Claude follows them as expected. Tests invoke Claude Code in headless mode (`claude -p`) and verify the behavior.

## Requirements

- Claude Code CLI installed and in PATH (`claude --version` should work)
- Local superpowers plugin installed (see main README for installation)

## Running Tests

### Run all fast tests (recommended):
```bash
./run-skill-tests.sh
```

### Run specific test:
```bash
./run-skill-tests.sh --test test-subagent-driven-development.sh
```

### Run with verbose output:
```bash
./run-skill-tests.sh --verbose
```

### Set custom timeout:
```bash
./run-skill-tests.sh --timeout 1800  # 30 minutes
```

## Test Structure

### test-helpers.sh
Common functions for skills testing:
- `run_claude "prompt" [timeout]` - Run Claude with prompt
- `assert_contains output pattern name` - Verify pattern exists
- `assert_not_contains output pattern name` - Verify pattern absent
- `assert_count output pattern count name` - Verify exact count
- `assert_order output pattern_a pattern_b name` - Verify order
- `create_test_project` - Create temp test directory
- `create_test_plan project_dir` - Create sample plan file

### Test Files

Each test file:
1. Sources `test-helpers.sh`
2. Runs Claude Code with specific prompts
3. Verifies expected behavior using assertions
4. Returns 0 on success, non-zero on failure

## Example Test

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: My Skill ==="

# Ask Claude about the skill
output=$(run_claude "What does the my-skill skill do?" 30)

# Verify response
assert_contains "$output" "expected behavior" "Skill describes behavior"

echo "=== All tests passed ==="
```

## Current Tests

### Fast Tests (run by default)

#### test-subagent-driven-development.sh
Asks a fresh agent nine questions only the loaded skill answers (~2 minutes).
Each answer has a fixed shape with closed choices, checked against the value
the skill text gives (cited in the test):
- Skill is loaded (ledger `progress.md`, the `task-brief` script)
- One task reviewer per task, with both verdicts
- Self-review required, never a replacement for the task review
- Plan read once, before Task 1
- Reviewer verifies the report's claims against the diff
- Fix loop: an implementer fixes, scoped re-review, five rounds at most
- Task delivered as a brief file; nobody reads the whole plan
- Workspace via using-git-worktrees; no start on main without consent

Every check runs even after one fails. One run is one sample per question.

### Integration Tests

None in this fork. Upstream's `test-subagent-driven-development-integration.sh`
ran `claude` with permission checks bypassed on a generated project; it was
removed rather than kept behind a flag.

#### test-worktree-native-preference.sh
Checks that the agent creates a worktree with the native EnterWorktree tool,
as using-git-worktrees Step 1a says, judging by the tool calls in claude's
stream-json output rather than the reply text. Needs `node`.
- GREEN: a plain request for an isolated workspace
- PRESSURE: the same under urgency, with a pre-existing gitignored `.worktrees/`
- `all` (default) runs both; a second argument sets runs per phase

Upstream's RED phase (the skill without Step 1a) is gone: the test never builds
that older skill, so against the current one it could only fail.

## Adding New Tests

1. Create new test file: `test-<skill-name>.sh`
2. Source test-helpers.sh
3. Write tests using `run_claude` and assertions
4. Add to test list in `run-skill-tests.sh`
5. Make executable: `chmod +x test-<skill-name>.sh`

## Timeout Considerations

- Default timeout: 5 minutes per test
- Claude Code may take time to respond
- Adjust with `--timeout` if needed
- Tests should be focused to avoid long runs

## Debugging Failed Tests

With `--verbose`, you'll see full Claude output:
```bash
./run-skill-tests.sh --verbose --test test-subagent-driven-development.sh
```

Without verbose, only failures show output.

## CI/CD Integration

To run in CI:
```bash
# Run with explicit timeout for CI environments
./run-skill-tests.sh --timeout 900

# Exit code 0 = success, non-zero = failure
```

## Notes

- Tests verify skill *instructions*, not full execution
- Full workflow tests would be very slow
- Focus on verifying key skill requirements
- Tests should be deterministic
- Avoid testing implementation details
