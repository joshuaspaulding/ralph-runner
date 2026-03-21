#!/bin/bash
# One-time AWS infrastructure setup:
#   - ECR repository
#   - ECS cluster
#   - IAM roles (execution + task)
#   - CloudWatch log group
#   - Security group
#
# Usage: ./deploy/setup.sh

set -euo pipefail

DIR="$(dirname "$0")"
source "$DIR/config.env"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"

echo "Setting up Ralph infrastructure in ${AWS_REGION} (account: ${AWS_ACCOUNT_ID})..."

# ECR repository
echo "Creating ECR repository..."
aws ecr create-repository \
  --region "$AWS_REGION" \
  --repository-name "$ECR_REPO" \
  --image-scanning-configuration scanOnPush=true \
  2>/dev/null && echo "  Created ${ECR_REPO}" || echo "  ${ECR_REPO} already exists"

# ECS cluster
echo "Creating ECS cluster..."
aws ecs create-cluster \
  --region "$AWS_REGION" \
  --cluster-name "$ECS_CLUSTER" \
  --capacity-providers FARGATE \
  2>/dev/null && echo "  Created cluster ${ECS_CLUSTER}" || echo "  Cluster ${ECS_CLUSTER} already exists"

# CloudWatch log group
echo "Creating CloudWatch log group..."
aws logs create-log-group \
  --region "$AWS_REGION" \
  --log-group-name "$LOG_GROUP" \
  2>/dev/null && echo "  Created ${LOG_GROUP}" || echo "  ${LOG_GROUP} already exists"

# IAM execution role
echo "Creating IAM execution role..."
aws iam create-role \
  --role-name ralph-execution-role \
  --assume-role-policy-document file://"$DIR/iam/trust-policy.json" \
  2>/dev/null && echo "  Created ralph-execution-role" || echo "  ralph-execution-role already exists"

aws iam put-role-policy \
  --role-name ralph-execution-role \
  --policy-name ralph-execution-policy \
  --policy-document file://"$DIR/iam/execution-role-policy.json"

# IAM task role
echo "Creating IAM task role..."
aws iam create-role \
  --role-name ralph-task-role \
  --assume-role-policy-document file://"$DIR/iam/trust-policy.json" \
  2>/dev/null && echo "  Created ralph-task-role" || echo "  ralph-task-role already exists"

aws iam put-role-policy \
  --role-name ralph-task-role \
  --policy-name ralph-task-policy \
  --policy-document file://"$DIR/iam/task-role-policy.json"

# Security group (outbound HTTPS only)
echo "Creating security group..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name ralph-runner \
  --description "Ralph runner — outbound HTTPS only" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text \
  2>/dev/null) && echo "  Created security group ${SG_ID}" || {
    SG_ID=$(aws ec2 describe-security-groups \
      --region "$AWS_REGION" \
      --filters "Name=group-name,Values=ralph-runner" "Name=vpc-id,Values=${VPC_ID}" \
      --query "SecurityGroups[0].GroupId" \
      --output text)
    echo "  Security group already exists: ${SG_ID}"
  }

# Allow outbound HTTPS
aws ec2 authorize-security-group-egress \
  --region "$AWS_REGION" \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 \
  2>/dev/null || true

# Revoke default allow-all egress rule if present
aws ec2 revoke-security-group-egress \
  --region "$AWS_REGION" \
  --group-id "$SG_ID" \
  --protocol -1 \
  --port -1 \
  --cidr 0.0.0.0/0 \
  2>/dev/null || true

# Save resolved config for other scripts
cat > "$DIR/.resolved.env" <<EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
ECR_REPO=${ECR_REPO}
ECS_CLUSTER=${ECS_CLUSTER}
TASK_FAMILY=${TASK_FAMILY}
LOG_GROUP=${LOG_GROUP}
VPC_ID=${VPC_ID}
SG_ID=${SG_ID}
EOF

echo
echo "Setup complete. Resolved config saved to deploy/.resolved.env"
echo "Next steps:"
echo "  1. make secrets    — store API keys in Secrets Manager"
echo "  2. make push       — build and push Docker image to ECR"
echo "  3. make ralph REPO=org/repo  — run Ralph against a repo"
