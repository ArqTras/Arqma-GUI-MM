#!/usr/bin/env bash
# Delete old GitHub Actions workflow runs, keeping only the newest N (default 3).
#
# Usage (repo root):
#   bash build/ci/prune-github-actions-runs.sh [owner/repo] [keep_count]
#
# Env: GH_TOKEN or GITHUB_TOKEN (actions:write), ARQMA_ACTIONS_RUNS_KEEP (default 3).
set -euo pipefail

REPO="${1:-${GITHUB_REPOSITORY:-}}"
KEEP="${2:-${ARQMA_ACTIONS_RUNS_KEEP:-3}}"

if [[ -z "${REPO}" ]]; then
  echo "usage: $0 [owner/repo] [keep_count]" >&2
  exit 1
fi

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "${TOKEN}" ]]; then
  echo "error: GH_TOKEN or GITHUB_TOKEN required" >&2
  exit 1
fi

if ! [[ "${KEEP}" =~ ^[0-9]+$ ]] || [[ "${KEEP}" -lt 1 ]]; then
  echo "error: keep_count must be a positive integer (got: ${KEEP})" >&2
  exit 1
fi

ids=()
page=1
while true; do
  resp="$(gh api "repos/${REPO}/actions/runs?per_page=100&page=${page}")"
  count="$(jq -r '.workflow_runs | length' <<<"${resp}")"
  [[ "${count}" -eq 0 ]] && break
  while IFS= read -r row; do
    ids+=("$(jq -r '.id' <<<"${row}")")
  done < <(jq -c '.workflow_runs[]' <<<"${resp}")
  total="$(jq -r '.total_count' <<<"${resp}")"
  if (( page * 100 >= total )); then
    break
  fi
  page=$((page + 1))
done

total_runs="${#ids[@]}"
if (( total_runs <= KEEP )); then
  echo "Nothing to prune on ${REPO} (${total_runs} run(s), keep ${KEEP})"
  exit 0
fi

deleted=0
skipped=0
for (( i = KEEP; i < total_runs; i++ )); do
  id="${ids[$i]}"
  status="$(gh api "repos/${REPO}/actions/runs/${id}" --jq '.status')"
  if [[ "${status}" == "in_progress" || "${status}" == "queued" || "${status}" == "waiting" || "${status}" == "pending" ]]; then
    echo "skip ${id} (${status})"
    skipped=$((skipped + 1))
    continue
  fi
  echo "delete ${id}"
  gh api -X DELETE "repos/${REPO}/actions/runs/${id}" >/dev/null
  deleted=$((deleted + 1))
  sleep 0.2
done

echo "Pruned ${deleted} run(s) on ${REPO}; kept ${KEEP} newest; skipped ${skipped} active"
