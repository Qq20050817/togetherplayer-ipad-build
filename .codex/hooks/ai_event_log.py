#!/usr/bin/env python3
"""Best-effort, metadata-only Codex event journal. Never records prompts or tool payloads."""
from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
EVENT_FILE = ROOT / ".ai" / "logs" / "codex-events.jsonl"
ALLOWED_EVENTS = {"SessionStart", "PostToolUse", "Stop", "Interrupt"}


def _safe(value: object, limit: int = 100) -> str | None:
    if not isinstance(value, str):
        return None
    if 0 < len(value) <= limit and all(c.isalnum() or c in "-_.:" for c in value):
        return value
    return None


def _status(response: object) -> str:
    if isinstance(response, dict):
        if response.get("isError") is True or response.get("is_error") is True:
            return "error"
        for key in ("exit_code", "exitCode"):
            if isinstance(response.get(key), int) and not isinstance(response.get(key), bool):
                return "ok" if response[key] == 0 else "error"
    return "unknown"


def main() -> None:
    try:
        event = json.load(sys.stdin)
        if not isinstance(event, dict):
            return
        name = event.get("hook_event_name")
        if name not in ALLOWED_EVENTS:
            return
        entry = {
            "time_utc": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "event": name,
            "session_id": _safe(event.get("session_id")),
            "turn_id": _safe(event.get("turn_id")),
        }
        if name == "PostToolUse":
            entry["tool"] = _safe(event.get("tool_name"), 160)
            entry["tool_use_id"] = _safe(event.get("tool_use_id"))
            entry["result"] = _status(event.get("tool_response"))
        # Store no cwd, commands, diffs, user prompts, tool arguments, tool outputs, or credentials.
        EVENT_FILE.parent.mkdir(parents=True, exist_ok=True)
        payload = (json.dumps(entry, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
        handle = os.open(str(EVENT_FILE), os.O_CREAT | os.O_APPEND | os.O_WRONLY, 0o600)
        try:
            os.write(handle, payload)
        finally:
            os.close(handle)
        if name == "SessionStart":
            print("Before editing, read AGENTS.md, AI_MEMORY.md, AI_ISSUES.md, and the latest AI_LOG.md entries. Check git status, verified release baseline, and current branch.")
    except (OSError, ValueError, TypeError, UnicodeError):
        # Logging must not prevent the primary development task from continuing.
        pass


if __name__ == "__main__":
    main()
