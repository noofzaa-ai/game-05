#!/usr/bin/env bash
# macOS/Linux entry point. Python's standard library handles portable timeouts,
# gzip, hashing and JSON without requiring GNU timeout, jq or PowerShell.
set -euo pipefail
PIPELINE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3.9+ is required." >&2
  exit 1
fi
exec python3 "$PIPELINE_DIR/build_web.py" "$@"
