#!/bin/bash
while true; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Starting fresh Ralph iteration (Claude 4 Sonnet)..."
  
  cat .ralph/PROMPT.md | claude-code \
    --dangerously-skip-permissions \
    --model claude-4-sonnet-latest \
    --output-format json

  git add -A && git commit -m "ralph: iteration complete [auto]" 2>/dev/null || true
  git push

  echo "Iteration done. Sleeping 5s..."
  sleep 5
done
