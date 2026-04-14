#!/bin/bash

GUARDRAILS=".ralph/guardrails.md"
MAX_FAILURES=3        # consecutive failures before stopping the run
MAX_ISSUE_FAILURES=3  # per-issue failures before skipping for this run

CONSECUTIVE_FAILURES=0
declare -A ISSUE_FAILURE_COUNT
SKIP_ISSUES=""  # space-separated issue numbers to skip this run

capture_guardrail() {
  local context="$1"
  local raw="$2"

  local hash
  hash=$(echo "$context$raw" | sha256sum | cut -c1-8)

  grep -q "<!-- $hash -->" "$GUARDRAILS" 2>/dev/null && return 0

  local rule
  rule=$(printf "Context: %s\nError: %s" "$context" "$raw" | claude \
    --model claude-haiku-4-5-20251001 \
    -p "Convert this error into one imperative guardrail rule. Max 15 words. Start with Never or Always. Output only the rule." 2>/dev/null)

  [ -z "$rule" ] && return 1
  echo "- $rule <!-- $hash -->" >> "$GUARDRAILS"
  echo "[guardrail appended] $rule"
}

# Count open issues excluding ralph/in-review labels and locally-skipped issues.
count_actionable_issues() {
  local numbers
  numbers=$(gh issue list --state open --json number,labels \
    --jq '[.[] | select(.labels | map(.name) | contains(["ralph/in-review"]) | not)] | .[].number | tostring' \
    2>/dev/null)

  local count=0
  while IFS= read -r num; do
    [ -z "$num" ] && continue
    # Skip issues that have failed too many times this run
    if [[ " $SKIP_ISSUES " != *" $num "* ]]; then
      count=$((count + 1))
    fi
  done <<< "$numbers"
  echo "$count"
}

while true; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  OPEN_ISSUES=$(count_actionable_issues)
  if [ "${OPEN_ISSUES:-0}" -eq 0 ]; then
    echo "No open issues. Ralph is done."
    exit 0
  fi

  echo "Starting fresh Ralph iteration ($OPEN_ISSUES open issue(s))..."

  export RALPH_SKIP_ISSUES="$SKIP_ISSUES"
  python3 /usr/local/bin/ralph-agent 2>&1 | tee /tmp/ralph_out
  exit_code=${PIPESTATUS[0]}

  OUT=$(cat /tmp/ralph_out)
  # Fatal API errors — no point retrying, exit immediately
  if echo "$OUT" | grep -qiE "credit balance|invalid api key|authentication|billing"; then
    echo "[fatal] API error — stopping loop"
    exit 1
  fi

  if [ $exit_code -ne 0 ]; then
    # Extract issue number from branch creation logged in tool output
    ISSUE_NUM=$(grep -oP '(?<=checkout -b ralph/)[0-9]+' /tmp/ralph_out | head -1)
    if [ -n "$ISSUE_NUM" ]; then
      ISSUE_FAILURE_COUNT[$ISSUE_NUM]=$(( ${ISSUE_FAILURE_COUNT[$ISSUE_NUM]:-0} + 1 ))
      if [ "${ISSUE_FAILURE_COUNT[$ISSUE_NUM]}" -ge "$MAX_ISSUE_FAILURES" ]; then
        echo "[ralph] issue #$ISSUE_NUM failed ${ISSUE_FAILURE_COUNT[$ISSUE_NUM]} times — skipping for this run"
        SKIP_ISSUES="$SKIP_ISSUES $ISSUE_NUM"
      fi
    fi

    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    if [ "$CONSECUTIVE_FAILURES" -ge "$MAX_FAILURES" ]; then
      echo "[ralph] $MAX_FAILURES consecutive failures — stopping"
      exit 1
    fi

    capture_guardrail "claude invocation" "$OUT"
  else
    CONSECUTIVE_FAILURES=0
  fi

  echo "Iteration done. Sleeping 5s..."
  sleep 5
done
