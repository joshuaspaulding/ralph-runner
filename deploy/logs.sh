#!/bin/bash
# Tail CloudWatch logs for the last Ralph task.
#
# Usage: ./deploy/logs.sh [task-arn]

set -euo pipefail

DIR="$(dirname "$0")"
source "$DIR/.resolved.env"

TASK_ARN="${1:-$(cat "$DIR/.last-task-arn" 2>/dev/null || echo "")}"

if [ -z "$TASK_ARN" ]; then
  echo "No task ARN found. Pass one explicitly or run 'make ralph' first."
  exit 1
fi

# Task ID is the last segment of the ARN
TASK_ID="${TASK_ARN##*/}"
LOG_STREAM="${LOG_GROUP#/}/ralph/${TASK_ID}"

echo "Tailing logs for task ${TASK_ID}..."
echo "  Log group:  ${LOG_GROUP}"
echo "  Log stream: ralph/${TASK_ID}"
echo

aws logs tail \
  --region "$AWS_REGION" \
  --follow \
  "${LOG_GROUP}" \
  --log-stream-name-prefix "ralph/${TASK_ID}"
