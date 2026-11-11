#!/usr/bin/env bash
# Local checks + render only. Never calls kubectl, applies manifests, or publishes images.
set -euo pipefail
pipeline_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$pipeline_dir/.." && pwd)"
if [[ $# -lt 1 || ( "$1" != staging && "$1" != prod ) ]]; then
  echo "Usage: $0 staging|prod [render options: --host HOST --ingress-class CLASS --tls-secret NAME --backup-image IMAGE@sha256:DIGEST]" >&2
  exit 2
fi
environment="$1"
shift
cd "$project_root"
python3 -m unittest discover -s tests -p test_online_infra.py
mkdir -p "build/online/$environment"
# Write atomically so a failed validation leaves the previous rendered artifact intact.
target="build/online/$environment/resources.json"
temporary="$(mktemp "${target}.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
python3 server/k3s/render.py --environment "$environment" "$@" > "$temporary"
mv -- "$temporary" "$target"
echo "Prepared $target. Review it; no cluster changes were made."
