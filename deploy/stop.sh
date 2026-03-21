#!/bin/bash
# Stop the last running Ralph task.
#
# Usage: ./deploy/stop.sh [task-arn]

set -euo pipefail

DIR="$(dirname "$0")"
source "$DIR/.resolved.env"

TASK_ARN="${1:-$(cat "$DIR/.last-task-arn" 2>/dev/null || echo "")}"

if [ -z "$TASK_ARN" ]; then
  echo "No task ARN found. Pass one explicitly or run 'make ralph' first."
  exit 1
fi

echo "Stopping task ${TASK_ARN}..."
aws ecs stop-task \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --task "$TASK_ARN" \
  --reason "Stopped by user" \
  --query "task.lastStatus" \
  --output text

echo "Done."
