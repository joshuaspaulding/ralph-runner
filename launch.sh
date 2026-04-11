#!/usr/bin/env bash
# Usage: launch.sh <org/repo>
# Clones repo, applies config overrides, runs ralph-runner Docker container.
# Credentials: sources ~/.hermes/.env (shared with openclaw/hermes), then
# ~/.ralph/config for overrides or GH_TOKEN if not set by hermes.
set -euo pipefail

REPO="${1:?Usage: launch.sh <org/repo>}"
SLUG="${REPO//\//-}"
CONFIG_DIR="$HOME/.ralph"
WORKDIR="$(mktemp -d "/tmp/ralph-${SLUG}-XXXXXX")"

# Load credentials — hermes .env first (has ANTHROPIC_API_KEY), then ralph
# config for anything not already set (e.g. GH_TOKEN).
# shellcheck source=/dev/null
[ -f "$HOME/.hermes/.env" ] && source "$HOME/.hermes/.env"
# shellcheck source=/dev/null
[ -f "$CONFIG_DIR/config" ] && source "$CONFIG_DIR/config"

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY not set — add to ~/.hermes/.env or ~/.ralph/config}"
: "${GH_TOKEN:?GH_TOKEN not set — add to ~/.ralph/config}"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "[ralph] Cloning ${REPO} into ${WORKDIR}..."
git clone "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" "$WORKDIR"
cd "$WORKDIR"
git config user.email "ralph@ralph-runner"
git config user.name "Ralph"
git remote set-url origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"

# Config resolution: repo-local > per-repo override on claw > ralph-runner defaults
RALPH_RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
for f in PROMPT.md guardrails.md; do
  if [ ! -f ".ralph/$f" ]; then
    mkdir -p .ralph
    if [ -f "$CONFIG_DIR/repos/$REPO/$f" ]; then
      echo "[ralph] Using per-repo override: ~/.ralph/repos/$REPO/$f"
      cp "$CONFIG_DIR/repos/$REPO/$f" ".ralph/$f"
    else
      echo "[ralph] Using default: $RALPH_RUNNER_DIR/.ralph/$f"
      cp "$RALPH_RUNNER_DIR/.ralph/$f" ".ralph/$f"
    fi
  else
    echo "[ralph] Using repo-local: .ralph/$f"
  fi
done

echo "[ralph] Starting container for ${REPO}..."
podman run --rm \
  --name "ralph-${SLUG}-$$" \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e GITHUB_TOKEN="$GH_TOKEN" \
  -v "$WORKDIR:/workspace" \
  ralph-runner

echo "[ralph] Done."
