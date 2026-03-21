#!/bin/bash
# One-time setup: store credentials as GitHub repo secrets on ralph-runner.
# Requires gh CLI authenticated with repo access.
#
# Usage: ./setup-secrets.sh

set -euo pipefail

GH_REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git//')

echo "Storing secrets on ${GH_REPO}..."

read -rsp "Anthropic API key (sk-ant-...): " ANTHROPIC_KEY
echo
gh secret set ANTHROPIC_API_KEY --repo "$GH_REPO" --body "$ANTHROPIC_KEY"

echo "GitHub PAT — needs repo + issues + pull_request scopes on target repos"
echo "(tip: gh auth token gives you your current token if it has those scopes)"
echo
read -rsp "GitHub PAT (ghp_...): " GH_PAT
echo
gh secret set GH_PAT --repo "$GH_REPO" --body "$GH_PAT"

echo
echo "Done. Secrets set on ${GH_REPO}:"
echo "  ANTHROPIC_API_KEY"
echo "  GH_PAT"
