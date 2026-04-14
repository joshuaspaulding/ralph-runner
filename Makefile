.PHONY: secrets ralph stop logs deploy help

GH_REPO := $(shell git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git//')
REPO ?=
DEPLOY_HOST ?= ralph-runner
DEPLOY_DIR := /opt/ralph-runner

help:
	@echo "Ralph Runner"
	@echo ""
	@echo "First-time setup:"
	@echo "  make secrets          Store ANTHROPIC_API_KEY and GH_PAT as repo secrets"
	@echo "  make deploy           Deploy to remote host (DEPLOY_HOST=$(DEPLOY_HOST))"
	@echo ""
	@echo "Daily use:"
	@echo "  make ralph REPO=org/repo  Start Ralph via GitHub Actions"
	@echo "  make logs                 Watch the latest run"
	@echo "  make stop                 Cancel the latest run"

secrets:
	@bash setup-secrets.sh

ralph:
	@test -n "$(REPO)" || (echo "Usage: make ralph REPO=org/repo" && exit 1)
	gh workflow run ralph.yml --repo $(GH_REPO) -f repo="$(REPO)"
	@echo "Ralph started. Run 'make logs' to watch."

logs:
	@RUN_ID=$$(gh run list --repo $(GH_REPO) --workflow ralph.yml --limit 1 --json databaseId --jq '.[0].databaseId'); \
	gh run watch --repo $(GH_REPO) $$RUN_ID

stop:
	@RUN_ID=$$(gh run list --repo $(GH_REPO) --workflow ralph.yml --limit 1 --json databaseId --jq '.[0].databaseId'); \
	gh run cancel --repo $(GH_REPO) $$RUN_ID && echo "Cancelled run $$RUN_ID"

deploy:
	ssh $(DEPLOY_HOST) "sudo mkdir -p $(DEPLOY_DIR) && sudo chown $$USER:$$USER $(DEPLOY_DIR)"
	rsync -av --exclude='.git' --exclude='.ruff_cache' . $(DEPLOY_HOST):$(DEPLOY_DIR)/
	ssh $(DEPLOY_HOST) "cd $(DEPLOY_DIR) && podman build -t ralph-runner -f dockerfile ."
	ssh $(DEPLOY_HOST) "mkdir -p ~/.ralph/repos && touch ~/.ralph/config"
	@echo ""
	@echo "Deployed to $(DEPLOY_HOST):$(DEPLOY_DIR)"
	@echo ""
	@echo "Next steps on the deploy host:"
	@echo "  1. Edit ~/.ralph/config:"
	@echo "       ANTHROPIC_API_KEY=sk-ant-..."
	@echo "       GH_TOKEN=ghp_...   (needs: repo, issues, pull_requests scopes)"
	@echo "     then: chmod 600 ~/.ralph/config"
	@echo ""
	@echo "  2. Install the Hermes skill (if applicable):"
	@echo "       cp -r $(DEPLOY_DIR)/hermes-skill ~/.hermes/skills/ralph"
	@echo ""
	@echo "  3. Test a run:"
	@echo "       $(DEPLOY_DIR)/launch.sh org/repo"
	@echo ""
	@echo "Tip: set DEPLOY_HOST in ~/.ssh/config to avoid passing it on every invocation:"
	@echo "  Host ralph-runner"
	@echo "    HostName <your-host-ip>"
	@echo "    User <your-user>"
