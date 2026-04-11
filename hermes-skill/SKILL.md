---
name: ralph
description: Run Ralph — an autonomous GitHub issue agent — against a repository to automatically work through open issues
version: 1.0.0
metadata:
  hermes:
    tags: [github, automation, ai-agent, issues, coding]
    related_skills: []
---

# Ralph Runner

Run Ralph — an autonomous Claude-powered agent — against a GitHub repository.
Ralph picks up open issues, writes code, opens PRs, and exits when the queue is empty.

## Trigger

Activate when the user says something like:
- "run ralph on org/repo"
- "start ralph for org/repo"
- "launch ralph against org/repo"
- "ralph org/repo"
- "have ralph work on org/repo"

## Inputs

Extract the **repository** in `org/repo` format from the user's message.
If the user omits the org (e.g. "run ralph on myrepo"), ask: "Which org is that under?"

## What it does

1. Clones the target repo to a temporary workspace on the claw server
2. Applies any per-repo prompt/guardrail overrides from `~/.ralph/repos/<org>/<repo>/`
3. Runs the `ralph-runner` Docker container — Ralph iterates until all open issues have PRs
4. Reports back with a summary of what Ralph did (last ~2000 chars of output)

Takes anywhere from 1 minute (no open issues) to 30+ minutes depending on issue count.

## Procedure

Call the `run` function from `run.py` with the extracted `org/repo` string.
Stream progress to the user if possible; otherwise report the final output summary.

If the run fails (non-zero exit):
- Check the output for "credit balance" or "billing" → tell the user to top up their Anthropic account
- Check for "invalid api key" → tell the user to update `ANTHROPIC_API_KEY` in `~/.ralph/config` on claw
- Otherwise report the tail of the error output

## Per-repo configuration

To customise Ralph's instructions for a specific repo without touching the repo itself:
```bash
mkdir -p ~/.ralph/repos/org/repo
# Then edit:
#   ~/.ralph/repos/org/repo/PROMPT.md       (Ralph's task instructions)
#   ~/.ralph/repos/org/repo/guardrails.md   (constraints / rules)
```

Config resolution order (first found wins):
1. `.ralph/PROMPT.md` already committed in the target repo
2. `~/.ralph/repos/<org>/<repo>/PROMPT.md` on claw (your override)
3. `/opt/ralph-runner/.ralph/PROMPT.md` (ralph-runner defaults)
