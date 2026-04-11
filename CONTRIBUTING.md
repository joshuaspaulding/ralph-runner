# Contributing

## Prerequisites

- **bash** — required to run scripts and tests
- **[gh CLI](https://cli.github.com/)** — used by Ralph to interact with GitHub (issues, PRs, workflows)
- **[claude](https://docs.anthropic.com/en/docs/claude-code)** — Anthropic's Claude CLI, used for guardrail generation

## Running tests

```bash
bash test-ralph-loop.sh
```

Tests validate `ralph-loop.sh` behaviour (loop exit conditions, git hygiene, API error handling, etc.).

## Running Ralph locally

Point Ralph at any GitHub repo using:

```bash
make ralph REPO=org/repo
```

This triggers the `ralph.yml` GitHub Actions workflow, which runs Ralph against the target repo.  
Use `make logs` to tail the run and `make stop` to cancel it.

> **First-time setup:** run `make secrets` to store your `ANTHROPIC_API_KEY` and `GH_PAT` as repo secrets before invoking Ralph.
