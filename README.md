# ralph-runner

> An autonomous Claude Code agent that runs in a loop, picking up GitHub issues and shipping code.

![Ralph Wiggum](https://i.kym-cdn.com/entries/icons/original/000/037/585/yeyey.jpg)

*"I'm helping!"* — Ralph Wiggum (and also this repo)

---

## What is this?

`ralph-runner` is a Docker-based harness for running **Ralph** — an autonomous Claude Code agent that:

1. Reads a prompt from `.ralph/PROMPT.md`
2. Runs `claude-code` against a mounted project workspace
3. Commits and pushes any changes
4. Sleeps 5 seconds and does it all again, forever

Ralph doesn't stop. Ralph doesn't complain. Ralph just ships.

---

## Quick Start

### 1. Clone this repo into your project

```bash
git clone https://github.com/joshuaspaulding/ralph-runner.git .ralph-runner
```

### 2. Set up your prompt

```bash
cp .ralph/guardrails.md.example .ralph/guardrails.md
# Edit .ralph/PROMPT.md to describe Ralph's task
```

### 3. Configure environment variables

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export GITHUB_TOKEN=ghp_...
export PROJECT_DIR=/path/to/your/project
export PROJECT_NAME=my-project
```

### 4. Run Ralph

```bash
docker-compose up --build
```

Ralph will start iterating immediately.

---

## How it works

```
┌─────────────────────────────────────────┐
│              Docker Container            │
│                                         │
│  ┌──────────────────────────────────┐   │
│  │          ralph-loop.sh           │   │
│  │                                  │   │
│  │  while true:                     │   │
│  │    cat .ralph/PROMPT.md          │   │
│  │      | claude-code               │   │
│  │    git commit & push             │   │
│  │    sleep 5                       │   │
│  └──────────────────────────────────┘   │
│                                         │
│  /workspace → your project (mounted)    │
└─────────────────────────────────────────┘
```

---

## Files

| File | Purpose |
|------|---------|
| `dockerfile` | Builds the Ralph container (Ubuntu + gh + claude-code) |
| `docker-compose.yml` | Mounts your project and wires up credentials |
| `ralph-loop.sh` | The main loop — runs Claude, commits, repeats |
| `.ralph/PROMPT.md` | Ralph's instructions (edit this for your project) |
| `.ralph/guardrails.md.example` | Example guardrails to keep Ralph on the rails |

---

## Tips

- **Guardrails matter.** Ralph runs with `--dangerously-skip-permissions`. Put constraints in `.ralph/guardrails.md` or he will do whatever seems like a good idea at the time.
- **Point him at issues.** The default prompt tells Ralph to pull tasks from GitHub Issues — give him a backlog and walk away.
- **He will commit a lot.** That's the point. Review the log when you get back.
