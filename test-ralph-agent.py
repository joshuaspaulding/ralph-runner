#!/usr/bin/env python3
"""
Tests for ralph-agent.py — run with: python3 test-ralph-agent.py
"""

import importlib.util
import json
import os
import sys
from unittest.mock import MagicMock, patch

PASS = 0
FAIL = 0
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def ok(name):
    global PASS
    print(f"PASS: {name}")
    PASS += 1


def fail(name, reason=""):
    global FAIL
    note = f" — {reason}" if reason else ""
    print(f"FAIL: {name}{note}")
    FAIL += 1


def load_agent(env_overrides=None):
    """Load ralph-agent.py as a module with optional env overrides."""
    env_overrides = env_overrides or {}
    for k, v in env_overrides.items():
        os.environ[k] = v
    path = os.path.join(SCRIPT_DIR, "ralph-agent.py")
    spec = importlib.util.spec_from_file_location("ralph_agent", path)
    mod = importlib.util.module_from_spec(spec)
    os.environ.setdefault("WORKSPACE", "/tmp")
    spec.loader.exec_module(mod)
    return mod


def make_tool_use_response():
    """Build a mock API response that requests a tool call."""
    mock_tool = MagicMock()
    mock_tool.type = "tool_use"
    mock_tool.name = "bash"
    mock_tool.id = "tu_test_123"
    mock_tool.input = {"command": "echo hello"}

    resp = MagicMock()
    resp.stop_reason = "tool_use"
    resp.content = [mock_tool]
    resp.usage.input_tokens = 100
    resp.usage.output_tokens = 20
    resp.usage.cache_read_input_tokens = 0
    resp.usage.cache_creation_input_tokens = 0
    return resp


# ── T-agent-1: tool output truncation ────────────────────────────────────────
try:
    mod = load_agent()
    # Generate output longer than MAX_TOOL_OUTPUT (default 2000)
    big_cmd = f"python3 -c 'print(\"x\" * {mod.MAX_TOOL_OUTPUT * 3})'"
    result = mod._dispatch("bash", {"command": big_cmd})
    if result.startswith("[...truncated") and len(result) <= mod.MAX_TOOL_OUTPUT + 80:
        ok("T-agent-1: tool output capped at MAX_TOOL_OUTPUT, tail preserved")
    else:
        fail("T-agent-1: tool output truncation", f"len={len(result)}, start={result[:60]}")
except Exception as e:
    fail("T-agent-1: tool output truncation", str(e))


# ── T-agent-2: MAX_TURNS cap exits with code 1 ───────────────────────────────
try:
    mod = load_agent({"RALPH_MAX_TURNS": "2"})
    resp = make_tool_use_response()

    mock_client = MagicMock()
    mock_client.messages.create.return_value = resp

    with patch.object(mod.anthropic, "Anthropic", return_value=mock_client), \
         patch.object(mod, "build_user_message", return_value="test prompt"), \
         patch.object(mod, "build_system", return_value=[]):
        exit_code = mod.run()

    # turn > MAX_TURNS fires at top of loop before the API call, so
    # MAX_TURNS=2 triggers on turn 3 → only 2 actual API calls made.
    if exit_code == 1 and mock_client.messages.create.call_count == 2:
        ok("T-agent-2: MAX_TURNS=2 stops loop after 2 API calls, returns exit 1")
    else:
        fail("T-agent-2: MAX_TURNS cap",
             f"exit_code={exit_code}, api_calls={mock_client.messages.create.call_count}")
except Exception as e:
    fail("T-agent-2: MAX_TURNS cap", str(e))
finally:
    os.environ.pop("RALPH_MAX_TURNS", None)


# ── T-agent-3: ralph/in-review issues filtered from build_user_message ───────
try:
    mod = load_agent()

    issues_json = json.dumps([
        {"number": 1, "title": "open issue",    "labels": [],                            "body": "", "assignees": []},
        {"number": 2, "title": "in-review",     "labels": [{"name": "ralph/in-review"}], "body": "", "assignees": []},
        {"number": 3, "title": "another open",  "labels": [],                            "body": "", "assignees": []},
    ])

    with patch.object(mod, "tool_bash", return_value=issues_json), \
         patch.object(mod, "_read", return_value=None):
        msg = mod.build_user_message()

    if "in-review" not in msg and '"number": 1' in msg and '"number": 3' in msg:
        ok("T-agent-3: ralph/in-review issues stripped from message sent to model")
    else:
        fail("T-agent-3: issue filtering", f"unexpected content in message")
except Exception as e:
    fail("T-agent-3: issue filtering", str(e))


# ── T-agent-4: RALPH_SKIP_ISSUES filtered from build_user_message ────────────
try:
    mod = load_agent()
    os.environ["RALPH_SKIP_ISSUES"] = "2"

    issues_json = json.dumps([
        {"number": 1, "title": "keep",   "labels": [], "body": "", "assignees": []},
        {"number": 2, "title": "skip me","labels": [], "body": "", "assignees": []},
    ])

    with patch.object(mod, "tool_bash", return_value=issues_json), \
         patch.object(mod, "_read", return_value=None):
        msg = mod.build_user_message()

    if '"number": 2' not in msg and '"number": 1' in msg:
        ok("T-agent-4: RALPH_SKIP_ISSUES issue stripped from message sent to model")
    else:
        fail("T-agent-4: RALPH_SKIP_ISSUES filtering", "issue 2 still present in message")
except Exception as e:
    fail("T-agent-4: RALPH_SKIP_ISSUES filtering", str(e))
finally:
    os.environ.pop("RALPH_SKIP_ISSUES", None)


# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\nResults: {PASS} passed, {FAIL} failed")
sys.exit(0 if FAIL == 0 else 1)
