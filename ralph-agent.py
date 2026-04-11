#!/usr/bin/env python3
"""
ralph-agent: one iteration of the Ralph agentic loop via the Anthropic SDK.

Caching layout (render order: tools → system → messages):
  system[0]  PROMPT.md + guardrails.md     ← cache_control: ephemeral (stable across iterations)
  system[1]  workspace CLAUDE.md           ← cache_control: ephemeral (if present)
  messages[0] user: open issues + prev     ← no cache_control (changes every iteration)

With a 5-second sleep between iterations the 5-minute cache TTL is more than
sufficient for cache hits on the static system blocks.

Note: the Sonnet 4.6 minimum cacheable prefix is ~2048 tokens. If PROMPT.md +
guardrails alone is shorter than that, caching activates only when a workspace
CLAUDE.md is also present. cache_creation_input_tokens=0 in the usage log means
the prefix was below the minimum — not an error, just no cache written.
"""

import json
import os
import subprocess
import sys

import anthropic

WORKSPACE = os.environ.get("WORKSPACE", "/workspace")
RALPH_DIR = os.path.join(WORKSPACE, ".ralph")
PREV_OUTPUT_FILE = "/tmp/ralph_out"
MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6")
MAX_TOKENS = int(os.environ.get("RALPH_MAX_TOKENS", "8192"))


# ── helpers ──────────────────────────────────────────────────────────────────

def _read(path: str) -> str | None:
    try:
        with open(path) as f:
            return f.read()
    except (FileNotFoundError, PermissionError):
        return None


# ── tools ────────────────────────────────────────────────────────────────────

def tool_bash(command: str) -> str:
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=WORKSPACE,
            capture_output=True,
            text=True,
            timeout=300,
        )
    except subprocess.TimeoutExpired:
        return "[error] command timed out after 5 minutes"

    parts = []
    if result.stdout:
        parts.append(result.stdout)
    if result.stderr:
        parts.append(f"[stderr]\n{result.stderr}")
    if result.returncode != 0:
        parts.append(f"[exit {result.returncode}]")
    return "\n".join(parts) if parts else "(no output)"


def tool_read_file(path: str) -> str:
    full = path if os.path.isabs(path) else os.path.join(WORKSPACE, path)
    content = _read(full)
    return content if content is not None else f"[error] file not found: {path}"


def tool_write_file(path: str, content: str) -> str:
    full = path if os.path.isabs(path) else os.path.join(WORKSPACE, path)
    try:
        os.makedirs(os.path.dirname(full) or ".", exist_ok=True)
        with open(full, "w") as f:
            f.write(content)
        return f"[ok] wrote {len(content)} bytes to {path}"
    except Exception as e:
        return f"[error] {e}"


TOOLS = [
    {
        "name": "bash",
        "description": (
            "Run a shell command in /workspace. Use for git, gh CLI, running "
            "tests, and any other shell operations. stdout and stderr are both "
            "captured and returned."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Shell command to execute"}
            },
            "required": ["command"],
        },
    },
    {
        "name": "read_file",
        "description": (
            "Read the full contents of a file. Path can be absolute or "
            "relative to /workspace."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "File path"}},
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": (
            "Write content to a file (creates or overwrites). Path can be "
            "absolute or relative to /workspace."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path"},
                "content": {"type": "string", "description": "Content to write"},
            },
            "required": ["path", "content"],
        },
    },
]


def _dispatch(name: str, inp: dict) -> str:
    if name == "bash":
        return tool_bash(inp["command"])
    if name == "read_file":
        return tool_read_file(inp["path"])
    if name == "write_file":
        return tool_write_file(inp["path"], inp["content"])
    return f"[error] unknown tool: {name}"


# ── prompt assembly ──────────────────────────────────────────────────────────

def build_system() -> list[dict]:
    """
    Static system blocks with cache_control so repeated iterations hit the
    cache instead of paying full input-token cost.
    """
    blocks: list[dict] = []

    prompt_md = _read(os.path.join(RALPH_DIR, "PROMPT.md"))
    guardrails_md = _read(os.path.join(RALPH_DIR, "guardrails.md"))

    static = ""
    if prompt_md:
        static += f"# Ralph Instructions\n\n{prompt_md}\n\n"
    if guardrails_md:
        static += f"# Guardrails\n\n{guardrails_md}\n"

    if static:
        blocks.append({
            "type": "text",
            "text": static,
            "cache_control": {"type": "ephemeral"},
        })

    # Workspace project context — also stable between iterations
    claude_md = (
        _read(os.path.join(WORKSPACE, ".claude", "CLAUDE.md"))
        or _read(os.path.join(WORKSPACE, "CLAUDE.md"))
    )
    if claude_md:
        blocks.append({
            "type": "text",
            "text": f"# Project Context (CLAUDE.md)\n\n{claude_md}",
            "cache_control": {"type": "ephemeral"},
        })

    return blocks


def build_user_message() -> str:
    """Dynamic content: previous iteration output + live open-issues list."""
    parts: list[str] = []

    prev = _read(PREV_OUTPUT_FILE)
    if prev and prev.strip():
        if len(prev) > 3000:
            prev = "[...truncated...]\n" + prev[-3000:]
        parts.append(f"## Previous Iteration Output\n\n```\n{prev.strip()}\n```\n")

    issues = tool_bash(
        "gh issue list --state open "
        "--json number,title,body,assignees,labels 2>/dev/null"
    )
    parts.append(f"## Current Open Issues\n\n{issues}\n")

    parts.append(
        "Begin your iteration. Follow the instructions in the system prompt exactly."
    )

    return "\n".join(parts)


# ── agent loop ───────────────────────────────────────────────────────────────

def run() -> int:
    client = anthropic.Anthropic()
    system_blocks = build_system()
    messages: list[dict] = [{"role": "user", "content": build_user_message()}]

    while True:
        try:
            response = client.messages.create(
                model=MODEL,
                max_tokens=MAX_TOKENS,
                system=system_blocks,
                tools=TOOLS,
                messages=messages,
            )
        except anthropic.AuthenticationError as e:
            print(f"[fatal] invalid api key: {e}", flush=True)
            return 1
        except anthropic.PermissionDeniedError as e:
            print(f"[fatal] billing/permission error: {e}", flush=True)
            return 1
        except anthropic.APIError as e:
            print(f"[error] API error: {e}", flush=True)
            return 1

        # Log cache stats on every turn
        u = response.usage
        cache_read = getattr(u, "cache_read_input_tokens", 0) or 0
        cache_created = getattr(u, "cache_creation_input_tokens", 0) or 0
        print(
            f"[usage] in={u.input_tokens} out={u.output_tokens} "
            f"cache_read={cache_read} cache_created={cache_created}",
            flush=True,
        )

        # Print text blocks and collect tool calls
        tool_uses = []
        for block in response.content:
            if block.type == "text" and block.text:
                print(block.text, flush=True)
            elif block.type == "tool_use":
                tool_uses.append(block)

        if not tool_uses or response.stop_reason == "end_turn":
            break

        # Execute tools
        tool_results = []
        for tu in tool_uses:
            preview = json.dumps(tu.input)[:120]
            print(f"[tool:{tu.name}] {preview}", flush=True)
            result = _dispatch(tu.name, tu.input)
            out_preview = result[:300] + "..." if len(result) > 300 else result
            print(f"  → {out_preview}", flush=True)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": tu.id,
                "content": result,
            })

        messages.append({"role": "assistant", "content": response.content})
        messages.append({"role": "user", "content": tool_results})

    return 0


if __name__ == "__main__":
    sys.exit(run())
