#!/bin/bash
# Start a Ralph task in ECS Fargate against a target repo.
#
# Usage: ./deploy/run.sh org/repo

set -euo pipefail

PROJECT_REPO="${1:-${PROJECT_REPO:-}}"
if [ -z "$PROJECT_REPO" ]; then
  echo "Usage: $0 <org/repo>  (or set PROJECT_REPO env var)"
  exit 1
fi

DIR="$(dirname "$0")"
source "$DIR/.resolved.env"

IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest"

# Get a public subnet from the default VPC
SUBNET_ID=$(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=defaultForAz,Values=true" \
  --query "Subnets[0].SubnetId" \
  --output text)

# Register (or update) the task definition
echo "Registering task definition..."
TASK_DEF=$(PROJECT_REPO="$PROJECT_REPO" \
  AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID" \
  AWS_REGION="$AWS_REGION" \
  ECR_REPO="$ECR_REPO" \
  TASK_FAMILY="$TASK_FAMILY" \
  LOG_GROUP="$LOG_GROUP" \
  envsubst < "$DIR/task-definition.tmpl.json")

TASK_DEF_ARN=$(echo "$TASK_DEF" \
  | aws ecs register-task-definition \
      --region "$AWS_REGION" \
      --cli-input-json /dev/stdin \
      --query "taskDefinition.taskDefinitionArn" \
      --output text)

echo "Task definition: ${TASK_DEF_ARN}"

# Run the task
echo "Starting Ralph against ${PROJECT_REPO}..."
TASK_ARN=$(aws ecs run-task \
  --region "$AWS_REGION" \
  --cluster "$ECS_CLUSTER" \
  --task-definition "$TASK_DEF_ARN" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_ID}],securityGroups=[${SG_ID}],assignPublicIp=ENABLED}" \
  --query "tasks[0].taskArn" \
  --output text)

echo "$TASK_ARN" > "$DIR/.last-task-arn"

echo
echo "Ralph is running!"
echo "  Task ARN: ${TASK_ARN}"
echo "  Repo:     ${PROJECT_REPO}"
echo
echo "  Logs:  make logs"
echo "  Stop:  make stop"
