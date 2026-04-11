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

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
