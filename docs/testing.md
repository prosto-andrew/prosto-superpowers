# Testing superpowers-custom

All plugin tests live in `tests/`. Upstream's skill-behavior eval lab
(`evals/`, a separate repository) is not part of this fork.

## Offline, bash and git only

These run on a plain Windows Git Bash install and need nothing else:

- `tests/no-egress/test-no-egress.sh` — the fork's main guard: no URL to a
  non-loopback host in code, no raw network API, no auto-loaded remote
  resource in skills, every network command in a skill gated and allowlisted,
  and none of the removed telemetry, remote-bind, upstream-reporting or
  permission-bypass code back in the tree. Run it after every upstream merge.
- `tests/no-egress/test-guard-self.sh` — the guard's own test: it seeds a
  throwaway repository with paths out (an upper-case `HTTPS://`, an install
  command, a remote image in an SVG) and checks the guard reports each one.
- `tests/shell-lint/test-lint-shell.sh` — tests `scripts/lint-shell.sh` with
  stub tools. Linting the real scripts with that script needs `shellcheck`
  (and `shfmt` for `--format`).
- `tests/claude-code/test-worktree-path-policy.sh`,
  `tests/claude-code/test-sdd-workspace.sh`,
  `tests/claude-code/test-executing-plans-scripts.sh` — the SDD and
  plan-execution helper scripts. They also prove the LF rule in
  `.gitattributes` works, since a CRLF checkout makes those scripts fail.
- `tests/systematic-debugging/test-find-polluter.sh`.

## Needs Node.js

- `tests/hooks/test-session-start.sh` — SessionStart hook output shapes.
- `tests/writing-skills/test-render-graphs.sh`.
- `tests/brainstorm-server/` — the visual companion server. `npm test` there
  needs one `npm install`, which downloads the `ws` test client from
  registry.npmjs.org; that is a deliberate, manual network step.
  `windows-lifecycle.test.sh` runs separately (Git Bash only, over 60 s).

## Other tools

- `tests/version-bump/test-bump-version.sh` — needs `jq` and `yq`.
- `tests/hermes/` — Python tests for the Hermes plugin
  (`python -m pytest tests/hermes`).
- `tests/codex/test-marketplace-manifest.sh` — Codex marketplace manifest.
  Calls `python3`; in Windows Git Bash that name can be the Microsoft Store
  stub, so put a real Python 3 on PATH under that name first.

## Calls the model

These need the `claude` CLI on PATH and signed in (`claude auth login`).

- `tests/claude-code/test-subagent-driven-development.sh` runs `claude -p`
  against the installed plugin (not the working tree) and costs tokens. It uses
  normal permission checks. Upstream's tests that bypassed them were removed.
- `tests/claude-code/test-worktree-native-preference.sh [red|green|pressure|all] [runs]`
  also runs `claude -p`, once per run, to check that the agent prefers native
  worktree tools. It is not in `run-skill-tests.sh`; run it by hand.
