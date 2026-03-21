# Guardrails — NEVER DELETE OR MODIFY THESE RULES

## Safety
- Never commit directly to main or master.
- Never force-push any branch.
- Never delete branches you did not create.
- Never commit secrets, API keys, `.env` files, or credentials.
- Never run destructive commands (rm -rf, DROP TABLE, git reset --hard on shared branches) without explicit instruction in the issue.

## Scope
- Only work on one issue per iteration.
- Only modify files relevant to the current issue.
- Do not refactor, reformat, or rename things outside the issue scope.
- Do not open multiple PRs in a single iteration.

## Git hygiene
- Always pull latest main before branching.
- Always branch with the format `ralph/<issue-number>-<slug>`.
- Always reference the issue number in commit messages and PR body.
- Do not amend commits that have already been pushed.

## Failure handling
- If tests fail after your change, fix them before opening a PR.
- If you cannot fix failing tests within 3 attempts, comment on the issue explaining what you tried, then exit.
- If the issue description is ambiguous, comment asking for clarification, then exit. Do not guess.
- If you hit the same error twice in a row, append a new guardrail here before retrying.

## Loop discipline
- If no open issues exist, exit cleanly. Do not invent tasks.
- Do not re-open issues or PRs that are already closed.
- Do not comment on issues more than once per iteration.
