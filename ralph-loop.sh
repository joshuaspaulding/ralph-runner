#!/bin/bash

GUARDRAILS=".ralph/guardrails.md"

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

while true; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Exit cleanly if there are no open issues
  OPEN_ISSUES=$(gh issue list --state open --json number --jq length 2>/dev/null)
  if [ "${OPEN_ISSUES:-0}" -eq 0 ]; then
    echo "No open issues. Ralph is done."
    exit 0
  fi

  echo "Starting fresh Ralph iteration ($OPEN_ISSUES open issue(s))..."

  cat .ralph/PROMPT.md | claude \
    --dangerously-skip-permissions \
    --model claude-sonnet-4-6 2>/tmp/ralph_err
  exit_code=$?

  if [ $exit_code -ne 0 ]; then
    ERR=$(cat /tmp/ralph_err)
    # Fatal API errors — no point retrying
    if echo "$ERR" | grep -qiE "credit balance|invalid api key|authentication|billing"; then
      echo "[fatal] API error: $ERR"
      exit 1
    fi
    capture_guardrail "claude invocation" "$ERR"
  fi

  echo "Iteration done. Sleeping 5s..."
  sleep 5
done
