"""
ralph hermes skill — run.py

Called by Hermes when the user triggers the ralph skill.
Invokes launch.sh <org/repo>, captures output, returns a summary.
"""

import subprocess
from pathlib import Path

RALPH_RUNNER = Path("/opt/ralph-runner")
TAIL_CHARS = 2000


def run(repo: str) -> str:
    """
    Run ralph against a GitHub repo.

    Args:
        repo: Repository in "org/repo" format.

    Returns:
        Last TAIL_CHARS characters of combined stdout+stderr, or an error message.
    """
    launch = RALPH_RUNNER / "launch.sh"
    if not launch.exists():
        return f"[error] launch.sh not found at {launch} — run 'make deploy' first"

    result = subprocess.run(
        [str(launch), repo],
        capture_output=True,
        text=True,
        timeout=7200,  # 2-hour hard cap
    )

    out = (result.stdout or "") + (result.stderr or "")
    summary = out[-TAIL_CHARS:] if len(out) > TAIL_CHARS else out

    if result.returncode != 0:
        return f"[ralph failed — exit {result.returncode}]\n\n{summary}"

    return f"[ralph finished]\n\n{summary}"
