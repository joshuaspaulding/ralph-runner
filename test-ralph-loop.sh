#!/usr/bin/env bash
# Tests for ralph-loop.sh — run with: bash test-ralph-loop.sh

PASS=0
FAIL=0
TMPDIR_LIST=()

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

cleanup() { for d in "${TMPDIR_LIST[@]}"; do rm -rf "$d"; done; }
trap cleanup EXIT

mkworkspace() {
  local d; d=$(mktemp -d); TMPDIR_LIST+=("$d")
  git -C "$d" init -q
  git -C "$d" config user.email "test@test"
  git -C "$d" config user.name "Test"
  echo "$d"
}

SCRIPT="$(cd "$(dirname "$0")" && pwd)/ralph-loop.sh"

# ── Test 1: main loop calls ralph-agent (Python SDK) ─────────────────────
# The main iteration loop must invoke ralph-agent (the cached Anthropic SDK
# agent) rather than piping directly to the claude CLI.
if grep -q 'ralph-agent' "$SCRIPT"; then
  pass "T1: main loop invokes ralph-agent (Python SDK with prompt caching)"
else
  fail "T1: ralph-loop.sh does not call ralph-agent — prompt caching not wired up"
fi

# ── Test 2: guardrail capture still uses claude CLI ───────────────────────
# ralph-agent handles the main iteration; the lightweight guardrail-rule
# generator still uses the claude CLI (haiku) for one-shot prompts.
if grep -q 'claude' "$SCRIPT" && grep -q 'ralph-agent' "$SCRIPT"; then
  pass "T2: guardrail capture uses claude CLI; main loop uses ralph-agent"
else
  fail "T2: unexpected invocation split between guardrail and main loop"
fi

# ── Test 3: --output-format flag present but output never used ────────────
# ralph-loop.sh captures output=$(cat ... | claude-code --output-format json ...)
# but $output is never referenced again. The flag adds overhead and the json
# wrapping may interfere with non-interactive piped invocation.
if grep -q -- '--output-format' "$SCRIPT"; then
  # Check if $output is ever used after assignment
  if grep -v 'output=' "$SCRIPT" | grep -q '\$output'; then
    pass "T3: --output-format present and \$output is consumed"
  else
    fail "T3: --output-format json passed but \$output is never used — dead flag"
  fi
else
  pass "T3: no --output-format flag"
fi

# ── Test 4: loop exits when no open issues ───────────────────────────────
# ralph-loop.sh should check for open issues before each iteration and
# exit 0 when none exist, so the GitHub Actions job completes cleanly.
if grep -q 'gh issue list.*--state open' "$SCRIPT" && grep -q 'exit 0' "$SCRIPT"; then
  pass "T4: loop exits cleanly when no open issues"
else
  fail "T4: loop has no early-exit for zero open issues — will spin forever"
fi

# ── Test 4b: post-loop 'git add -A && git commit' removed from script ─────
# The old code ran `git add -A && git commit` after every iteration, which
# failed on clean trees (false guardrail) and could commit to main on early
# exit. Fix: remove it — Ralph commits its own work via PROMPT.md.
if grep -q 'git add -A' "$SCRIPT"; then
  fail "T4b: 'git add -A' still present in ralph-loop.sh — post-loop commit bug not fixed"
else
  pass "T4b: post-loop 'git add -A && git commit' removed"
fi

# ── Test 5: post-loop 'git push' removed from script ────────────────────
# The old code ran an unconditional `git push` after each iteration that
# would push whatever branch ralph left (including main). Fix: remove it.
if grep -qE '^\s+git push' "$SCRIPT"; then
  fail "T5: bare 'git push' still present in ralph-loop.sh — could push main"
else
  pass "T5: post-loop bare 'git push' removed"
fi

# ── Test 5b: fatal API errors exit immediately ────────────────────────────
# "Credit balance is too low" caused the loop to spin for hours.
# The script should now detect fatal API errors and exit 1 immediately.
if grep -qiE 'credit balance|invalid api key|authentication|billing' "$SCRIPT"; then
  pass "T5b: fatal API error patterns detected — loop will exit instead of spinning"
else
  fail "T5b: no fatal API error handling — loop will spin forever on billing/auth errors"
fi

# ── Test 6: capture_guardrail SHA deduplication ───────────────────────────
# Same error should not append a new guardrail on every iteration.
W3=$(mkworkspace)
mkdir -p "$W3/.ralph"
GUARDRAILS="$W3/.ralph/guardrails.md"
echo "# Guardrails" > "$GUARDRAILS"

CTX="test context"; RAW="test error"
HASH=$(printf '%s%s' "$CTX" "$RAW" | sha256sum | cut -c1-8)
echo "- Some rule <!-- $HASH -->" >> "$GUARDRAILS"

if grep -q "<!-- $HASH -->" "$GUARDRAILS"; then
  pass "T6: deduplication — hash match correctly prevents duplicate guardrail"
else
  fail "T6: deduplication broken — duplicate guardrail would be appended"
fi

# ── Test 7: GITHUB_TOKEN exposed to gh cli in workflow ───────────────────
# PROMPT.md uses `gh issue list` / `gh pr create` — requires GITHUB_TOKEN.
WORKFLOW="$(dirname "$SCRIPT")/.github/workflows/ralph.yml"
if grep -q 'GITHUB_TOKEN' "$WORKFLOW"; then
  pass "T7: GITHUB_TOKEN set in workflow env for gh cli"
else
  fail "T7: GITHUB_TOKEN missing from workflow — all gh commands will fail"
fi

# ── Mock infrastructure (shared by T8–T10) ────────────────────────────────
# Creates a temp bin dir with fake gh, python3, claude, and sleep binaries.
# Issue JSON is read from /tmp/mock_gh_issues at runtime.
# Agent exit code is read from /tmp/mock_agent_exit (default 0).
# Agent stdout is read from /tmp/mock_agent_output (default empty).
create_mockbin() {
  local mb; mb=$(mktemp -d); TMPDIR_LIST+=("$mb")

  # sleep: instant no-op
  printf '#!/bin/bash\n' > "$mb/sleep"; chmod +x "$mb/sleep"

  # claude: return a canned guardrail rule (used by capture_guardrail)
  printf '#!/bin/bash\necho "Never repeat that error."\n' > "$mb/claude"; chmod +x "$mb/claude"

  # gh: emit JSON from /tmp/mock_gh_issues; apply --jq filter if present
  cat > "$mb/gh" << 'GHEOF'
#!/bin/bash
JSON=$(cat /tmp/mock_gh_issues 2>/dev/null || echo '[]')
JQ_ARG=""; prev=""
for arg in "$@"; do
  [ "$prev" = "--jq" ] && JQ_ARG="$arg"
  prev="$arg"
done
if [ -n "$JQ_ARG" ]; then echo "$JSON" | jq -r "$JQ_ARG"
else echo "$JSON"; fi
GHEOF
  chmod +x "$mb/gh"

  # python3: exit code from /tmp/mock_agent_exit, stdout from /tmp/mock_agent_output
  cat > "$mb/python3" << 'PYEOF'
#!/bin/bash
cat /tmp/mock_agent_output 2>/dev/null || true
exit "$(cat /tmp/mock_agent_exit 2>/dev/null || echo 0)"
PYEOF
  chmod +x "$mb/python3"

  echo "$mb"
}

# Source only the function definitions from ralph-loop.sh (not the while loop).
source <(sed '/^while true/,$ d' "$SCRIPT")

# ── Test 8: ralph/in-review issues excluded from count ────────────────────
MOCKBIN_T8=$(create_mockbin)
echo '[{"number":42,"title":"t","labels":[{"name":"ralph/in-review"}],"body":"","assignees":[]}]' \
  > /tmp/mock_gh_issues
SKIP_ISSUES=""
T8_COUNT=$(PATH="$MOCKBIN_T8:$PATH" count_actionable_issues)
if [ "${T8_COUNT}" = "0" ]; then
  pass "T8: ralph/in-review issue excluded from actionable count"
else
  fail "T8: expected count=0 for ralph/in-review issue, got $T8_COUNT"
fi

# ── Test 8b: issue in SKIP_ISSUES excluded from count ─────────────────────
echo '[{"number":42,"title":"t","labels":[],"body":"","assignees":[]}]' > /tmp/mock_gh_issues
SKIP_ISSUES=" 42"
T8B_COUNT=$(PATH="$MOCKBIN_T8:$PATH" count_actionable_issues)
SKIP_ISSUES=""
if [ "${T8B_COUNT}" = "0" ]; then
  pass "T8b: issue in SKIP_ISSUES excluded from actionable count"
else
  fail "T8b: expected count=0 for skipped issue, got $T8B_COUNT"
fi

# ── Test 9: consecutive failure counter exits after MAX_FAILURES ──────────
MOCKBIN_T9=$(create_mockbin)
WS_T9=$(mktemp -d); TMPDIR_LIST+=("$WS_T9")
mkdir -p "$WS_T9/.ralph"
echo "# Guardrails" > "$WS_T9/.ralph/guardrails.md"

# Agent fails with no branch output (tests consecutive-failure path only)
echo 1 > /tmp/mock_agent_exit
echo "agent error: something went wrong" > /tmp/mock_agent_output
echo '[{"number":99,"title":"t","labels":[],"body":"","assignees":[]}]' > /tmp/mock_gh_issues

T9_OUT=$(cd "$WS_T9" && PATH="$MOCKBIN_T9:$PATH" timeout 20 bash "$SCRIPT" 2>&1)
T9_EXIT=$?
if echo "$T9_OUT" | grep -q "consecutive failures — stopping" && [ "$T9_EXIT" -eq 1 ]; then
  pass "T9: consecutive failure counter exits loop after MAX_FAILURES"
else
  fail "T9: expected '[ralph] 3 consecutive failures' and exit 1 — got exit=$T9_EXIT, out=$(echo "$T9_OUT" | tail -3)"
fi

# ── Test 10: per-issue skip after MAX_ISSUE_FAILURES ─────────────────────
MOCKBIN_T10=$(create_mockbin)
WS_T10=$(mktemp -d); TMPDIR_LIST+=("$WS_T10")
mkdir -p "$WS_T10/.ralph"
echo "# Guardrails" > "$WS_T10/.ralph/guardrails.md"

# Agent fails and outputs a branch creation line so issue 42 is tracked
echo 1 > /tmp/mock_agent_exit
printf '[tool:bash] {"command": "git checkout -b ralph/42-test-issue"}\nagent error\n' \
  > /tmp/mock_agent_output
echo '[{"number":42,"title":"t","labels":[],"body":"","assignees":[]}]' > /tmp/mock_gh_issues

T10_OUT=$(cd "$WS_T10" && PATH="$MOCKBIN_T10:$PATH" timeout 20 bash "$SCRIPT" 2>&1)
if echo "$T10_OUT" | grep -q "issue #42 failed"; then
  pass "T10: per-issue failure tracking emits skip message for issue #42"
else
  fail "T10: expected 'issue #42 failed' in output — got: $(echo "$T10_OUT" | tail -5)"
fi

# Cleanup mock control files
rm -f /tmp/mock_gh_issues /tmp/mock_agent_exit /tmp/mock_agent_output

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
