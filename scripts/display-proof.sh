#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=$(tr -d '[:space:]' < "$root/VisualProof/playwright-image.txt")

usage() {
  echo "usage: scripts/display-proof.sh export|verify|record" >&2
  exit 1
}

docker_run() {
  local runner=(docker)
  if ! docker info >/dev/null 2>&1; then
    runner=(sudo docker)
  fi
  "${runner[@]}" run --rm \
    --platform linux/amd64 \
    -v "$root:/work" \
    -w /work/VisualProof \
    -e HS_PROOF_CONTAINER=1 \
    -e TZ=UTC \
    -e PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    "$image" \
    bash -lc 'npm ci && npx playwright "$@"' bash "$@"
}

own_output() {
  if [ "$(id -u)" = "0" ]; then
    return
  fi
  sudo chown -R "$(id -u):$(id -g)" \
    "$root/Fixtures/DisplayProof/screenshots" \
    "$root/VisualProof/test-results" \
    "$root/VisualProof/node_modules" 2>/dev/null || true
}

case "${1:-}" in
  export)
    (cd "$root" && swift run home-signal display proof export --out Fixtures/DisplayProof)
    ;;
  verify)
    (cd "$root" && swift test)
    docker_run test
    own_output
    ;;
  record)
    (cd "$root" && swift run home-signal display proof export --out Fixtures/DisplayProof)
    docker_run test --update-snapshots=changed
    own_output
    ;;
  *)
    usage
    ;;
esac
