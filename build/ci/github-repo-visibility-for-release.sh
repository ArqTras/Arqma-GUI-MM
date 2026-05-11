#!/usr/bin/env bash
# GitHub Actions on private repos can incur minutes billing; public repos do not charge the same way.
# Use this script so visibility is public BEFORE pushes that trigger CI (commit/tag/release), then
# private again after the Tauri workflow run finishes.
#
# If secret `ARQMA_REPO_VISIBILITY_PAT` is set in the repo, the Tauri workflow job
# `repo-private-after-build` switches the repository to private after tag builds (no local script).
#
# Typical flow:
#   1) ./build/ci/github-repo-visibility-for-release.sh public
#   2) git commit … && git push … && git tag vX.Y.Z && git push origin vX.Y.Z && gh release create …
#   3) ./build/ci/github-repo-visibility-for-release.sh watch-tauri --tag vX.Y.Z
#
# On **workflow_dispatch** of *Tauri app*, Actions also starts *Flutter GitHub Release* in parallel;
# `watch-tauri` only waits for Tauri — wait for the Flutter run separately if you need both before `private`.
#
# Environment: GH_TOKEN or gh auth (same as `gh`). Optional: GITHUB_REPOSITORY=owner/name
set -eu

REPO="${GITHUB_REPOSITORY:-}"
if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "error: set GITHUB_REPOSITORY=owner/repo or run from a repo where \`gh repo view\` works" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  github-repo-visibility-for-release.sh public
      Set repository to public (run this before git push / tag / release that starts CI).

  github-repo-visibility-for-release.sh private
      Set repository to private (run after CI if you skipped watch-tauri).

  github-repo-visibility-for-release.sh watch-tauri --tag vX.Y.Z
      Wait for the latest "Tauri app" workflow run for that tag, then set repository to private.
      Always restores private on exit (even if the workflow failed or watch was interrupted).

  github-repo-visibility-for-release.sh watch-tauri --run-id RUN_ID
      Wait for a specific workflow run, then set private.
EOF
}

set_private_always() {
  echo "[visibility] setting $REPO to private …"
  gh api -X PATCH "repos/$REPO" -f visibility=private >/dev/null
  gh repo view "$REPO" --json visibility,isPrivate -q '"visibility=" + .visibility + " private=" + (.isPrivate|tostring)'
}

cmd_public() {
  echo "[visibility] setting $REPO to public …"
  gh api -X PATCH "repos/$REPO" -f visibility=public >/dev/null
  gh repo view "$REPO" --json visibility,isPrivate -q '"visibility=" + .visibility + " private=" + (.isPrivate|tostring)'
}

cmd_private() {
  set_private_always
}

cmd_watch_tauri() {
  local tag="" run_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)
        tag="${2:-}"
        shift 2
        ;;
      --run-id)
        run_id="${2:-}"
        shift 2
        ;;
      *)
        echo "error: unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$run_id" ]]; then
    if [[ -z "$tag" ]]; then
      echo "error: pass --tag vX.Y.Z or --run-id RUN_ID" >&2
      usage >&2
      exit 1
    fi
    echo "[visibility] resolving latest Tauri app run for tag $tag …"
    run_id="$(
      gh run list -R "$REPO" --workflow=desktop-release.yml --branch "$tag" -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true
    )"
    if [[ -z "$run_id" || "$run_id" == "null" ]]; then
      echo "error: no workflow run found for branch/tag $tag (push the tag first?)" >&2
      exit 1
    fi
  fi

  trap 'set_private_always || true' EXIT

  echo "[visibility] watching run $run_id (repo stays public until this finishes) …"
  if gh run watch "$run_id" -R "$REPO" --exit-status; then
    echo "[visibility] workflow succeeded"
  else
    echo "[visibility] workflow failed or gh run watch exited non-zero" >&2
  fi
}

case "${1:-}" in
  public) cmd_public ;;
  private) cmd_private ;;
  watch-tauri)
    shift
    cmd_watch_tauri "$@"
    ;;
  ""|-h|--help|help) usage ;;
  *)
    echo "error: unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
