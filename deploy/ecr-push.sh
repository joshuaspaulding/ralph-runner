#!/bin/bash
# Build the Docker image and push it to ECR.
#
# Usage: ./deploy/ecr-push.sh

set -euo pipefail

DIR="$(dirname "$0")"
source "$DIR/.resolved.env"

IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest"

echo "Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "Building image..."
docker build -t "$ECR_REPO" "$(dirname "$DIR")"

echo "Tagging and pushing to ${IMAGE_URI}..."
docker tag "${ECR_REPO}:latest" "$IMAGE_URI"
docker push "$IMAGE_URI"

echo "Done: ${IMAGE_URI}"
