# superpowers-custom — Guidelines for Agents Working in This Repository

This repository is a custom fork of [obra/superpowers](https://github.com/obra/superpowers)
v6.4.2 (commit `8ca22db`), published as the default branch `custom` of the
**public** GitHub repository `prosto-andrew/prosto-superpowers`. Claude Code on
your human partner's machine loads the plugin straight from this working tree.
It exists for one reason: **nothing in it sends data
off the machine on its own, and nothing it tells an agent to do sends data
without an explicit yes from your human partner.** Every rule below serves that.

## The no-egress rule

- **Never add an outbound request to plugin code.** No remote URL in scripts,
  hooks, HTML, JS/TS or Python; no telemetry, no update check, no analytics, no
  remote logo, font, stylesheet or script. The brainstorm companion serves only
  same-origin resources and its Content-Security-Policy must keep refusing the
  rest.
- **Network commands in skills stay gated.** A skill may tell the agent to run
  `git pull`, `git push`, create a PR, call `gh api`, or install packages only
  behind the rule "Network commands need their own yes", worded identically in
  every file that carries it. Adding a new gated command means adding it to the
  allowlist in `tests/no-egress/test-no-egress.sh` with its reason.
- **`diagnosing-sessions` is local only.** It must never regain issue search or
  filing, bundles, archives, scrubbing for export, or any upload. Its structure
  test fails on any of them.
- **The companion binds loopback only.** Do not reintroduce a host option, a
  bind to all interfaces, or a shell-executed open command.
- **No test may bypass permission checks.** Upstream's tests that ran `claude`
  with permissions skipped were removed; do not bring them back.

## Before you finish any change

```bash
bash tests/no-egress/test-no-egress.sh
bash tests/diagnosing-sessions/test-skill-structure.sh
```

Both must pass. If the guard reports a hit, remove the path out — do not widen
the patterns or allowlist it to make the test green unless your human partner
has agreed that the specific line is harmless, and record the reason beside it.

## Merging from upstream

Upstream updates are pulled by your human partner, by hand, never
automatically. When asked to help with one:

1. Your human partner runs `git fetch upstream` themselves — it is a network
   command and needs their yes like any other.
2. Review `git diff custom upstream/main` for new URLs, telemetry, network
   commands, new harness code, and changes to the files this fork edited.
3. Merge, resolve, then run both tests above plus the shell tests in
   `docs/testing.md`. Re-read every new hit from the guard before touching it.
4. Bump the version in every file listed in `.version-bump.json` with
   `bash scripts/bump-version.sh <upstream version>-custom.1`, or Claude Code
   will not pick up the new copy.

The same goes for any change of your own: bump to `-custom.N+1` before you
finish, so the next session loads it.

## Skill content is behavior-shaping code

Carried over from upstream, and still true here:

- Skills are not prose — they shape agent behavior. Change them deliberately
  and test the change (`superpowers:writing-skills`).
- Do not modify carefully-tuned content (Red Flags tables, rationalization
  lists, "your human partner" language) without evidence the change is an
  improvement. "Your human partner" is deliberate, not interchangeable with
  "the user".
- Zero dependencies by design. Do not add third-party packages to the plugin.

**The acceptance test** for any change to the bootstrap or hooks: open a clean
session and send exactly

> Let's make a react todo list

A working install auto-triggers `brainstorming` before any code is written.

## Supported harnesses

Claude Code (`.claude-plugin/`, `hooks/`), Codex (`.codex-plugin/`, `.agents/`),
Gemini CLI (`gemini-extension.json`, `GEMINI.md`) and Hermes Agent
(`.hermes-plugin/`). Support for the others upstream ships was removed; do not
add a harness without your human partner asking for it.

## Public repository

Everything committed here ends up public once pushed, and a pushed secret
stays in history even after it is deleted. So:

- **Never commit** secrets, tokens, keys or `.env` files, session
  transcripts, `diagnosing-sessions` case files or reports, brainstorm
  workspaces (`.superpowers/`), local settings (`.claude/`), or
  machine-specific paths and names. Check `git status` and the staged diff
  before every commit.
- **Commits are authored `Andrew <>`** (set in this repository's local git
  config) and carry no `Claude-Session` trailer or session link.
- **Push only with your human partner's yes**, only to the `custom` branch of
  their fork, never with force. Work from another session (a cloud session,
  a helper branch) is reviewed and tested here before it lands in `custom`.
- **Keep this working tree on `custom`.** Claude Code loads the plugin from
  it, so checking out another branch changes the plugin every new session
  runs.

## Upstream

This fork does not contribute back and must never open issues or pull requests
against obra/superpowers. The upstream remote is named `upstream`; the working
branch is `custom`. The fork's `main` mirrors upstream, so `main...custom`
shows exactly what this fork changed.
