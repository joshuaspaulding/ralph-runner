#!/bin/bash
set -e

# If PROJECT_REPO is set, clone it (ECS mode).
# Otherwise assume /workspace is already mounted (local docker-compose mode).
if [ -n "${PROJECT_REPO:-}" ]; then
  # Normalize: accept "org/repo" or full "https://github.com/org/repo"
  REPO_SLUG="${PROJECT_REPO#https://github.com/}"
  REPO_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_SLUG}"

  echo "Cloning ${REPO_SLUG}..."
  git clone "$REPO_URL" /workspace
  cd /workspace

  # Point origin at authenticated URL so git push works
  git remote set-url origin "$REPO_URL"
  git config user.email "ralph@ralph-runner"
  git config user.name "Ralph"

  # If the repo has no .ralph/ config, copy defaults baked into the image
  if [ ! -f .ralph/PROMPT.md ]; then
    echo "No .ralph/PROMPT.md found — copying defaults from image"
    mkdir -p .ralph
    cp /ralph-defaults/PROMPT.md .ralph/PROMPT.md
  fi
  if [ ! -f .ralph/guardrails.md ]; then
    mkdir -p .ralph
    cp /ralph-defaults/guardrails.md .ralph/guardrails.md
  fi
else
  cd /workspace
fi

exec ralph-loop
