#!/usr/bin/env python3
"""Builds the Kiro CLI team agents (.kiro/agents/<name>.json, one file per agent) from the role files in
.claude/agents/<name>.md, so both Claude Code and Kiro use the same team. Edit the .md role, then run:

    python3 tools/kiro/sync_agents.py

Boss 2026-10-12: every team member runs on Opus 5.5. qa stays read-only (no write tool).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / ".claude" / "agents"
TARGET = ROOT / ".kiro" / "agents"
MODEL = "claude-opus-5.5"

WRITERS = ["read", "write", "shell", "grep", "glob", "code"]
READ_ONLY = ["read", "shell", "grep", "glob", "code"]

# Added to every prompt: how to run Godot on the Mac (the role files were written on Windows).
MAC_NOTE = """

## Running on the Mac (Boss moved to macOS 2026-10-12)
- Godot 4.7.2: `/Applications/Godot.app/Contents/MacOS/Godot` (use it wherever a rule says `godot`). Blender 4.5.10 LTS: `/Applications/Blender.app/Contents/MacOS/Blender`.
- macOS has no `timeout`; run with `perl -e 'alarm 900; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run_all.gd` and read stderr.
- Ignore any Windows-only hints (WinGet, `Godot_v*_console.exe`, PowerShell, `C:/...` paths).
- You are a Kiro CLI agent; \"the PO\" is the main Kiro session that delegated this task."""


def parse(path: Path):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not match:
        raise SystemExit(f"{path}: missing --- front matter ---")
    meta = {}
    for line in match.group(1).splitlines():
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip()
    return meta, match.group(2).strip()


def build(path: Path) -> dict:
    meta, body = parse(path)
    name = meta["name"]
    read_only = name == "qa"
    tools = READ_ONLY if read_only else WRITERS
    return {
        "name": name,
        "description": meta["description"],
        "prompt": body + MAC_NOTE,
        "model": MODEL,
        "tools": tools,
        "allowedTools": ["read", "grep", "glob", "code"],
        "toolsSettings": {"shell": {"autoAllowReadonly": True}},
        "resources": ["file://CLAUDE.md"],
    }


def main() -> None:
    TARGET.mkdir(parents=True, exist_ok=True)
    written = []
    for path in sorted(SOURCE.glob("*.md")):
        agent = build(path)
        out = TARGET / f"{agent['name']}.json"
        out.write_text(json.dumps(agent, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        written.append(out.relative_to(ROOT))
    for out in written:
        print(out)


if __name__ == "__main__":
    main()
