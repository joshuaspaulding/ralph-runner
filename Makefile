.PHONY: secrets ralph stop logs help

GH_REPO := $(shell git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git//')
REPO ?=

help:
	@echo "Ralph Runner"
	@echo ""
	@echo "First-time setup:"
	@echo "  make secrets              Store ANTHROPIC_API_KEY and GH_PAT as repo secrets"
	@echo ""
	@echo "Daily use:"
	@echo "  make ralph REPO=org/repo  Start Ralph against a GitHub repo"
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
