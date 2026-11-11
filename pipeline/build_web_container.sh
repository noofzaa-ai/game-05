#!/usr/bin/env bash
# Package the exported game into an Nginx runtime image. Does not start a server
# on the host, deploy, push an image or modify Git state.
set -euo pipefail
pipeline_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$pipeline_dir/.." && pwd)"
web_output="$project_root/build/web"
image_tag="zorx-web:local"
target_platform="linux/amd64"
export_first=false
usage() {
  cat <<'HELP'
Usage: ./pipeline/build_web_container.sh [options]
  --image TAG          Runtime image tag (default: zorx-web:local)
  --platform PLATFORM  Docker target platform (default: linux/amd64)
  --build-web          Run build_web.sh --max-file-mb 0 first (including tests)
  -h, --help           Show help

Without --build-web, packages the existing build/web/ export only.
Examples:
  ./pipeline/build_web_container.sh --image zorx-web:phase0
  ./pipeline/build_web_container.sh --build-web --image registry.example.com/zorx/web:phase0
  ./pipeline/build_web_container.sh --platform linux/arm64
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --image|--platform)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "ERROR: $1 requires a value." >&2; exit 2
      fi
      if [[ "$1" == --image ]]; then image_tag="$2"; else target_platform="$2"; fi
      shift 2 ;;
    --build-web) export_first=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is required." >&2; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Docker. Start Docker Desktop/daemon or check your Docker context." >&2
  exit 1
fi
if [[ "$export_first" == true ]]; then
  "$pipeline_dir/build_web.sh" --max-file-mb 0
fi
for required in play.html packs.json index.js; do
  if [[ ! -s "$web_output/$required" ]]; then
    echo "ERROR: Missing $web_output/$required. Run ./pipeline/build_web.sh --max-file-mb 0 first, or use --build-web." >&2
    exit 1
  fi
done
# The manifest is authoritative: reject a partial/missing export before Docker.
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: Python 3 is needed to read packs.json while packaging (not in the runtime image)." >&2; exit 1
fi
python3 - "$web_output" <<'PY'
import json, sys
from pathlib import Path
folder = Path(sys.argv[1]).resolve()
manifest = json.loads((folder / 'packs.json').read_text())
names = [manifest['engine'], manifest['core']] + [p['file'] for p in manifest['packs']]
for name in names:
    if not isinstance(name, str) or Path(name).name != name or name in ('.', '..'):
        raise SystemExit(f'ERROR: Expected a local pack filename, got {name!r}')
    path = folder / name
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f'ERROR: Missing or empty pack: {path}')
# A previous external CDN base would ignore the assets packaged in this image.
page = (folder / 'play.html').read_text()
if "window.ZORX_PACK_BASE = window.ZORX_PACK_BASE || '';" not in page:
    raise SystemExit('ERROR: This container expects same-origin packs. Rebuild Web without --pack-base.')
print('Packaging Web build:', manifest['build'])
PY
context_dir="$(mktemp -d "${TMPDIR:-/tmp}/zorx-web-container.XXXXXX")"
trap 'rm -rf -- "$context_dir"' EXIT
mkdir "$context_dir/html"
# Send only runtime files to Docker, never the repo, .git, sources or artifact-link metadata.
tar --exclude=.claude --exclude=.DS_Store -C "$web_output" -cf - . | tar -C "$context_dir/html" -xf -
cp "$pipeline_dir/maintenance.html" "$context_dir/html/maintenance.html"
cp "$pipeline_dir/Dockerfile.web" "$context_dir/Dockerfile"
cp "$pipeline_dir/nginx-web.conf" "$context_dir/nginx-web.conf"
docker build --platform "$target_platform" --tag "$image_tag" "$context_dir"
printf '\nRuntime image ready: %s (%s)\n' "$image_tag" "$target_platform"
printf 'Run: docker run --rm -p 8060:8080 %q\n' "$image_tag"
printf 'Play: http://localhost:8060/\n'
