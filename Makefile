.PHONY: secrets ralph stop logs deploy-claw help

GH_REPO := $(shell git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git//')
REPO ?=
CLAW := josh@100.101.101.68
CLAW_DIR := /opt/ralph-runner

help:
	@echo "Ralph Runner"
	@echo ""
	@echo "First-time setup:"
	@echo "  make secrets              Store ANTHROPIC_API_KEY and GH_PAT as repo secrets"
	@echo "  make deploy-claw          Deploy ralph to claw server ($(CLAW))"
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

deploy-claw:
	ssh $(CLAW) "sudo mkdir -p $(CLAW_DIR) && sudo chown josh:josh $(CLAW_DIR)"
	rsync -av --exclude='.git' --exclude='.ruff_cache' . $(CLAW):$(CLAW_DIR)/
	ssh $(CLAW) "cd $(CLAW_DIR) && docker build -t ralph-runner -f dockerfile ."
	ssh $(CLAW) "mkdir -p ~/.ralph/repos && touch ~/.ralph/config"
	@echo ""
	@echo "Deployed to $(CLAW):$(CLAW_DIR)"
	@echo ""
	@echo "Next steps on claw:"
	@echo "  1. Edit ~/.ralph/config:"
	@echo "       ANTHROPIC_API_KEY=sk-ant-..."
	@echo "       GH_TOKEN=ghp_...   (needs: repo, issues, pull_requests scopes)"
	@echo "     then: chmod 600 ~/.ralph/config"
	@echo ""
	@echo "  2. Install the Hermes skill:"
	@echo "       cp -r $(CLAW_DIR)/hermes-skill ~/.hermes/skills/ralph"
	@echo ""
	@echo "  3. Test directly (bypasses Hermes):"
	@echo "       $(CLAW_DIR)/launch.sh org/repo"
