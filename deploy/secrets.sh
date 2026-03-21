#!/bin/bash
# One-time setup: store credentials in AWS Secrets Manager.
# Run this once before deploying Ralph.
#
# Usage: ./deploy/secrets.sh

set -euo pipefail

source "$(dirname "$0")/config.env"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "Storing secrets in AWS Secrets Manager (region: ${AWS_REGION})..."

read -rsp "Anthropic API key (sk-ant-...): " ANTHROPIC_KEY
echo
read -rsp "GitHub token (ghp_...): " GH_TOKEN
echo

aws secretsmanager create-secret \
  --region "$AWS_REGION" \
  --name "ralph/anthropic-api-key" \
  --description "Anthropic API key for Ralph" \
  --secret-string "$ANTHROPIC_KEY" \
  2>/dev/null || \
aws secretsmanager put-secret-value \
  --region "$AWS_REGION" \
  --secret-id "ralph/anthropic-api-key" \
  --secret-string "$ANTHROPIC_KEY"

aws secretsmanager create-secret \
  --region "$AWS_REGION" \
  --name "ralph/github-token" \
  --description "GitHub token for Ralph" \
  --secret-string "$GH_TOKEN" \
  2>/dev/null || \
aws secretsmanager put-secret-value \
  --region "$AWS_REGION" \
  --secret-id "ralph/github-token" \
  --secret-string "$GH_TOKEN"

echo "Done. Secrets stored:"
echo "  ralph/anthropic-api-key"
echo "  ralph/github-token"
