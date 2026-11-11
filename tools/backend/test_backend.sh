#!/usr/bin/env bash
# Portable entry point; never enable shell tracing around credentials.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${PYTHON_BIN:-python3}" "$SCRIPT_DIR/smoke.py" "$@"
