#!/usr/bin/env bash
# macOS/Linux entry point. Python's standard library handles portable timeouts,
# gzip, hashing and JSON without requiring GNU timeout, jq or PowerShell.
set -euo pipefail
PIPELINE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Windows Git Bash: `python3` may be the Microsoft Store stub, which exists but cannot run.
# Use $PYTHON if set, else the first of python3/python that really executes.
pick_python() {
  local candidate
  for candidate in "${PYTHON:-}" python3 python; do
    [[ -n "$candidate" ]] || continue
    if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
      printf '%s' "$candidate"; return 0
    fi
  done
  return 1
}
if ! PY="$(pick_python)"; then
  echo "ERROR: Python 3.9+ is required (set PYTHON=/path/to/python if it is not on PATH)." >&2
  exit 1
fi
exec "$PY" "$PIPELINE_DIR/build_web.py" "$@"
