.PHONY: secrets setup push ralph stop logs help

# Run Ralph against a GitHub repo in ECS Fargate.
# Usage: make ralph REPO=org/repo
REPO ?=

help:
	@echo "Ralph Runner"
	@echo ""
	@echo "First-time setup (run once):"
	@echo "  make secrets          Store API keys in AWS Secrets Manager"
	@echo "  make setup            Create ECR, ECS cluster, IAM roles, security group"
	@echo "  make push             Build and push Docker image to ECR"
	@echo ""
	@echo "Daily use:"
	@echo "  make ralph REPO=org/repo   Start Ralph against a GitHub repo"
	@echo "  make logs                  Tail logs for the last task"
	@echo "  make stop                  Stop the last task"

secrets:
	@bash deploy/secrets.sh

setup:
	@bash deploy/setup.sh

push:
	@bash deploy/ecr-push.sh

ralph:
	@bash deploy/run.sh "$(REPO)"

stop:
	@bash deploy/stop.sh

logs:
	@bash deploy/logs.sh
