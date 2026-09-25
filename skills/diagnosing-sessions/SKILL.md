---
name: diagnosing-sessions
description: Use when a coding-agent session went wrong and your human partner wants to know why — repeated work, ignored plans, stumbles, poor results, a skill that didn't fire, "it took too long", "why is it so expensive", "what is it doing" — for the current session or a past one identified by id or path.
---

# Diagnosing Sessions

## Overview

Pin down with your human partner what went wrong in a session, read the
transcripts on disk, and report what happened with evidence. Everything stays
on this machine: the transcripts, the case file and the report. This skill has
no outbound path of any kind.

**Core principle:** Every finding cites `path:line`. No citation, no
finding. Every number comes from the transcript or from a command you ran,
never from memory.

## Workflow

Create a todo per step. Step 5 runs only when asked.

1. **Problem intake.** Ask one question at a time until you can write a
   statement naming the session(s), the turn range if known, what your
   partner expected, what happened, and the observable they care about
   (wall-clock, tokens, repeated actions, one specific action). "It took
   too long" is a complaint, not a problem statement.
2. **Locate.** Resolve each session to verified absolute filesystem paths
   using `references/session-discovery.md`; on Claude Code start from
   `references/claude-code-sessions.md`. Confirm a past session by quoting its
   first prompt and timestamp, and list every candidate you rejected with the
   reason, or "none". Enumerate subagent transcripts. Create
   `~/.superpowers/diagnosing-sessions/<session-id>/`, tell your partner the
   path, and fill `templates/case.md` there, following its provenance rules
   for environment and skill observations.
3. **Triage.** Read the region around the reported problem yourself. Then
   dispatch one analyst subagent per dimension in parallel, each given the
   case file path, `prompts/analyst-common.md`, and one dimension file from
   `prompts/`: `skill-timeline.md`, `plan-adherence.md`, `repeated-work.md`,
   `stumbles.md`, `quality-evidence.md`, `request-conflicts.md`,
   `cost-and-time.md`. Split a dimension by turn range when the transcript is
   long. Discard any returned finding without `path:line`.
4. **Report.** Fill every section of `templates/report.md` in order, write
   it to the workspace, show it, and give the path. Check what cited content
   actually proves.
5. **Similar sessions** — only when asked. Turn confirmed findings into a
   signature, list candidates on this machine by mtime and size, find marker
   line numbers, dispatch `prompts/similar-session.md` per candidate in
   parallel, and append report §9.

## Quick reference

All seven analysts always run. This table says which region to read
yourself in step 3 and which findings to lead with in the verdict.

| Complaint | Read first, lead with |
|---|---|
| "It took too long" | cost-and-time, stumbles |
| "Why did it do this extra work?" | repeated-work, plan-adherence |
| "Why is it so expensive?" | cost-and-time |
| "What the hell is it doing?" (still running) | skill-timeline; note in-progress in coverage |
| "It ignored the plan" | plan-adherence, compaction lines first |
| "Skill X never fired" | skill-timeline |

## Hard rules

- **Local only.** For the whole of this skill, and for every analyst it
  dispatches: no `gh`, `curl` or `wget`, no git remote commands, no web
  fetch or web search, no MCP or connector tool that sends data, no
  archive, no upload, no issue, no comment, no share link. Transcript
  content is copied nowhere except the workspace. If your partner wants to
  show the report to someone, they do that themselves after reading it: give
  the path and stop.
- **Workspace is sensitive.** The case file and report quote transcripts,
  which can carry secrets, internal hosts and colleagues' names. Keep the
  workspace under `~/.superpowers/`, never inside a project repository, and
  say so when you give the path.
- **Context safety.** One transcript line can be a megabyte. Follow
  `references/context-safety.md` on every session file, every time.
- **Read-only.** Never modify, move, or delete a session file.
- **Exact paths to subagents.** A subagent's "current session" is its
  own. Pass absolute paths and ids.
- **Human prompts only.** Hook output, system reminders, and tool results
  are not your partner's words. In a subagent transcript, "user" is the
  parent agent.
- **Report, don't fix.** Report §7 states involvement and stops. Never
  name a defect in a skill or propose a change. Your partner pressing for a
  fix does not waive this: the report is the input to that decision, which
  is made separately. No advice to your partner either.
- **Intake before analysis.** Nothing in steps 2–5 starts until your
  partner has answered. If they are away, write the questions and stop.
  A statement you reconstructed for them is not an answer. An
  already-scoped request — one specific event, what is running now, or
  the analysis to run — is itself the statement: answer it, then ask.
  A whole-session "why" is a complaint.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The problem is obvious, skip intake" | The problem statement scopes everything. Ask. |
| "They're away, so I'll reconstruct the statement" | You cannot reconstruct what they wanted. Write the questions and stop. |
| "I'll sweep everything now and ask at the end" | An unscoped sweep spends their budget on the wrong question. Ask first. |
| "They'll want to share this, so I'll package it" | Packaging or sending session data is not this skill's job. Give the path; your partner decides. |
| "A quick web search would explain this error" | Local only. Report the error with its `path:line`; looking it up is your partner's call. |
| "Small, targeted edit, no restructuring needed" | Not your call, however small. Report the evidence. |
| "The price per token is well known" | Numbers you did not compute from the transcript are invented. Cite or drop. |
