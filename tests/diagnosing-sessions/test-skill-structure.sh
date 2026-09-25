#!/usr/bin/env bash
# Structural checks for skills/diagnosing-sessions, the local-only replacement
# for upstream's diagnosing-superpowers. Checks what a shell can check:
# frontmatter, referenced files exist, SKILL.md word budget, no local paths or
# names leaked, and — the reason this fork has its own skill — nothing in it
# that sends session data anywhere.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/skills/diagnosing-sessions"
SKILL_MD="$SKILL_DIR/SKILL.md"
WORD_BUDGET=1000

PASSES=0
FAILURES=0

pass() { echo "  [PASS] $1"; PASSES=$((PASSES + 1)); }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

echo "diagnosing-sessions structure"

# --- SKILL.md frontmatter -------------------------------------------------
if [ -f "$SKILL_MD" ]; then
  pass "SKILL.md exists"
  frontmatter="$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$SKILL_MD")"
  if printf '%s\n' "$frontmatter" | grep -q '^name: diagnosing-sessions$'; then
    pass "frontmatter name is diagnosing-sessions"
  else
    fail "frontmatter name is diagnosing-sessions"
  fi
  description="$(printf '%s\n' "$frontmatter" | awk '/^description:/{sub(/^description:[ ]*/,""); print; found=1; next} found && /^[ ]/{print} found && !/^[ ]/{exit}' | tr '\n' ' ')"
  if printf '%s' "$description" | grep -q '^Use when'; then
    pass "description starts with 'Use when'"
  else
    fail "description starts with 'Use when' (got: ${description:0:60})"
  fi
  if [ "${#description}" -le 1024 ]; then
    pass "description under 1024 characters"
  else
    fail "description under 1024 characters (${#description})"
  fi
  for banned in "dispatch" "then" "step"; do
    if printf '%s' "$description" | grep -qiw "$banned"; then
      fail "description contains workflow word '$banned'"
    else
      pass "description avoids workflow word '$banned'"
    fi
  done

  # --- word budget --------------------------------------------------------
  body_words="$(awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm==2{print}' "$SKILL_MD" | wc -w | tr -d ' ')"
  if [ "$body_words" -le "$WORD_BUDGET" ]; then
    pass "SKILL.md body within $WORD_BUDGET words ($body_words)"
  else
    fail "SKILL.md body within $WORD_BUDGET words ($body_words)"
  fi

  # --- required sections and the rule this skill exists for ---------------
  for heading in "## Hard rules" "## Red Flags"; do
    if grep -q "^$heading" "$SKILL_MD"; then
      pass "SKILL.md has section '$heading'"
    else
      fail "SKILL.md has section '$heading'"
    fi
  done
  if grep -q '^- \*\*Local only\.\*\*' "$SKILL_MD"; then
    pass "Hard rules carry the Local only rule"
  else
    fail "Hard rules carry the Local only rule"
  fi
  if grep -q '^Local only:' "$SKILL_DIR/prompts/analyst-common.md" 2>/dev/null; then
    pass "analyst-common.md carries the Local only rule for subagents"
  else
    fail "analyst-common.md carries the Local only rule for subagents"
  fi

  # --- every referenced skill file exists --------------------------------
  while IFS= read -r ref; do
    if [ -f "$SKILL_DIR/$ref" ]; then
      pass "referenced file exists: $ref"
    else
      fail "referenced file exists: $ref"
    fi
  done < <(grep -o '\(references\|prompts\|templates\)/[A-Za-z0-9._-]*\.md' "$SKILL_MD" | sort -u)
else
  fail "SKILL.md exists"
fi

# --- expected files -------------------------------------------------------
expected_files=(
  references/session-discovery.md
  references/context-safety.md
  references/claude-code-sessions.md
  prompts/analyst-common.md
  prompts/skill-timeline.md
  prompts/plan-adherence.md
  prompts/repeated-work.md
  prompts/stumbles.md
  prompts/quality-evidence.md
  prompts/request-conflicts.md
  prompts/cost-and-time.md
  prompts/similar-session.md
  templates/case.md
  templates/report.md
)
for rel in "${expected_files[@]}"; do
  if [ -f "$SKILL_DIR/$rel" ]; then
    pass "expected file present: $rel"
  else
    fail "expected file present: $rel"
  fi
done

# --- the outbound half of upstream's skill stays out ---------------------
outbound_files=(
  references/github-issues.md
  references/redaction-policy.md
  prompts/scrub.md
  prompts/scrub-audit.md
  templates/issue.md
  templates/bundle-README.md
)
for rel in "${outbound_files[@]}"; do
  if [ ! -e "$SKILL_DIR/$rel" ]; then
    pass "outbound file absent: $rel"
  else
    fail "outbound file absent: $rel"
  fi
done
if [ ! -e "$REPO_ROOT/skills/diagnosing-superpowers" ]; then
  pass "upstream diagnosing-superpowers is not shipped"
else
  fail "upstream diagnosing-superpowers is not shipped"
fi

# --- no command that sends anything --------------------------------------
# Patterns match commands and URLs, not the prose that forbids them: the
# Local only rule names `gh`, `curl` and `wget` without arguments.
egress="$(grep -rn -i -E 'gh (issue|api|pr|search|repo|gist)|curl |wget |https?://|api\.github\.com|zip -r|tar -c|issue create|--body-file' "$SKILL_DIR" 2>/dev/null || true)"
if [ -z "$egress" ]; then
  pass "no network commands or URLs in the skill"
else
  fail "no network commands or URLs in the skill"
  printf '%s\n' "$egress" | head -10 | sed 's/^/    /'
fi

# --- no local paths or names in shipped files ----------------------------
leaks="$(grep -rn -E '/Users/|/home/|[A-Za-z]:\\Users\\|jesse' "$SKILL_DIR" "$SCRIPT_DIR" --exclude=test-skill-structure.sh 2>/dev/null || true)"
if [ -z "$leaks" ]; then
  pass "no machine-specific paths or names in shipped files (skills + tests)"
else
  fail "no machine-specific paths or names in shipped files (skills + tests)"
  printf '%s\n' "$leaks" | head -10 | sed 's/^/    /'
fi

# --- "the user" never appears in skill prose -----------------------------
user_hits="$(grep -rn -i 'the user' "$SKILL_DIR" --include='*.md' 2>/dev/null || true)"
if [ -z "$user_hits" ]; then
  pass "skill files say 'your human partner', not 'the user'"
else
  fail "skill files say 'your human partner', not 'the user'"
  printf '%s\n' "$user_hits" | head -10 | sed 's/^/    /'
fi

echo
echo "Passed: $PASSES  Failed: $FAILURES"
[ "$FAILURES" -eq 0 ]
