#!/usr/bin/env bash
# Build from this working tree and publish an image. Cluster rollout is manual.
set -euo pipefail
pipeline_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$pipeline_dir/.." && pwd)"
registry="${ZORX_REGISTRY:-wiyazard:30500}"
image_name="zorx-web"
target_platform="linux/amd64"
release_tag=""
usage() {
  cat <<'HELP'
Usage: ./pipeline/deploy_k3s.sh [options]
Build Web (including tests), build the runtime image, then push it to the registry.
Stops after push; change the image tag and deploy on k3s yourself.

  --tag TAG            Explicit release tag; default: git SHA + UTC timestamp
                       (adds -dirty when the working tree has local changes)
  --registry HOST      Registry host[:port] (default: wiyazard:30500 or ZORX_REGISTRY)
  --image-name NAME    Repository name (default: zorx-web)
  --platform PLATFORM Target platform (default: linux/amd64; ARM: linux/arm64)
  -h, --help          Show help

Examples:
  ./pipeline/deploy_k3s.sh
  ./pipeline/deploy_k3s.sh --tag mobile-v2
  ./pipeline/deploy_k3s.sh --platform linux/arm64

Uses the current working tree, including local changes; does not pull Git.
Requires Python 3.9+, Git, Docker, Godot 4.7.2 + Web templates and registry access.
Windows: run from Git Bash with Docker Desktop running and GODOT_BIN set
(see docs/tech/k3s_release_checklist.md).
Configure Docker registry authentication/HTTP registry access separately if needed.
HELP
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag|--registry|--image-name|--platform)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "ERROR: $1 requires a value." >&2; exit 2
      fi
      case "$1" in
        --tag) release_tag="$2" ;;
        --registry) registry="$2" ;;
        --image-name) image_name="$2" ;;
        --platform) target_platform="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ ! "$registry" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?$ ]]; then
  echo "ERROR: Registry must be a hostname[:port], without http:// or a path." >&2; exit 2
fi
if [[ ! "$image_name" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(/[a-z0-9]+([._-][a-z0-9]+)*)*$ ]]; then
  echo "ERROR: Invalid image repository name." >&2; exit 2
fi
if [[ "$target_platform" != linux/amd64 && "$target_platform" != linux/arm64 ]]; then
  echo "ERROR: Supported platforms: linux/amd64, linux/arm64." >&2; exit 2
fi
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
for dependency in git docker; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "ERROR: $dependency is required." >&2; exit 1
  fi
done
if ! pick_python >/dev/null; then
  echo "ERROR: Python 3.9+ is required (python3 or python; set PYTHON to override)." >&2; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot reach Docker. Start Docker Desktop (or the daemon) first." >&2; exit 1
fi
source_commit="$(git -C "$project_root" rev-parse --short=12 HEAD)"
source_state="$(git -C "$project_root" status --porcelain)"
if [[ -z "$release_tag" ]]; then
  release_tag="${source_commit}-$(date -u +%Y%m%dT%H%M%SZ)"
  if [[ -n "$source_state" ]]; then release_tag="${release_tag}-dirty"; fi
fi
if [[ ! "$release_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "ERROR: Invalid Docker tag (1-128 letters, digits, underscores, dots or dashes)." >&2; exit 2
fi
image_ref="${registry}/${image_name}:${release_tag}"
mkdir -p "$project_root/build"
lock_dir="$project_root/build/.image-publish.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "ERROR: Another image publish may be running ($lock_dir). Check it before removing a stale lock." >&2
  exit 1
fi
trap 'rm -rf -- "$lock_dir"' EXIT
printf '%s\n' "$$" > "$lock_dir/pid"
printf 'Source: %s\nImage: %s\nPlatform: %s\n' "$source_commit" "$image_ref" "$target_platform"
if [[ -n "$source_state" ]]; then
  printf 'Source includes uncommitted/untracked files in this working tree.\n'
fi
# Always rebuild; never package a stale build/web directory after an export failure.
"$pipeline_dir/build_web_container.sh" --build-web --image "$image_ref" --platform "$target_platform"
printf '\nPushing %s\n' "$image_ref"
docker push "$image_ref"
# Only record success after Docker confirms push. Also record the immutable digest so
# rollout and rollback use repo@sha256, never a tag that could be overwritten.
printf '%s\n' "$image_ref" > "$project_root/build/pushed-image.txt"
digest_ref="$(docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$image_ref" | grep -F "${registry}/${image_name}@" | head -n 1 || true)"
if [[ -n "$digest_ref" ]]; then
  printf '%s\n' "$digest_ref" >> "$project_root/build/pushed-image.txt"
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$source_commit" "$image_ref" "$digest_ref" >> "$project_root/build/pushed-images.log"
  printf 'Digest: %s\n' "$digest_ref"
else
  echo "WARNING: Docker reported no RepoDigest; copy the digest from the push output above." >&2
fi
printf '\nPush completed. Use this image in your k3s deployment:\n%s\n' "$image_ref"
printf 'Saved: %s/build/pushed-image.txt\n' "$project_root"
