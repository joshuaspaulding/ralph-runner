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
  echo "Starting fresh Ralph iteration..."

  output=$(cat .ralph/PROMPT.md | claude-code \
    --dangerously-skip-permissions \
    --model claude-sonnet-4-6 \
    --output-format json 2>/tmp/ralph_err)
  exit_code=$?

  [ $exit_code -ne 0 ] && capture_guardrail "claude-code invocation" "$(cat /tmp/ralph_err)"

  git add -A && git commit -m "ralph: iteration complete [auto]" 2>/tmp/ralph_git_err \
    || capture_guardrail "git commit" "$(cat /tmp/ralph_git_err)"

  git push 2>/tmp/ralph_push_err \
    || capture_guardrail "git push" "$(cat /tmp/ralph_push_err)"

  echo "Iteration done. Sleeping 5s..."
  sleep 5
done
