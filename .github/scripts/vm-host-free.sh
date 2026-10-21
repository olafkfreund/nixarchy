#!/usr/bin/env bash
# Is p620 free of the OTHER workflow's VM job? (#1365) Needs gh and jq; $GH is stubbable.
# Prints "free" (exit 0), "busy: <workflow> run <id> job <name>" (exit 1), exit 2 if unknown.
# install asks about omarchy-edge's `verify`; edge asks about install-check's `install`.
set -euo pipefail
case ${1:-} in
  install) wf=omarchy-edge.yml job=verify ;;
  edge) wf=install-check.yml job=install ;;
  *) echo "usage: vm-host-free.sh <install|edge>" >&2; exit 2 ;;
esac
repo=${GITHUB_REPOSITORY:?}
unknown() { echo "::warning::vm-host-free: $1; not known to be free" >&2; exit 2; }
# Capture first: a process substitution would hide a failed call and read as free (CLAUDE.md §4).
runs=$(${GH:-gh} api "repos/$repo/actions/runs?status=in_progress&per_page=50") || unknown "run list failed"
jq -e 'has("workflow_runs")' >/dev/null <<<"$runs" || unknown "run list unreadable"
ids=$(jq -r --arg p ".github/workflows/$wf" --arg me "${GITHUB_RUN_ID:-}" \
  '.workflow_runs[] | select(.path == $p and (.id|tostring) != $me) | .id' <<<"$runs") || unknown "run list unreadable"
for id in $ids; do
  jobs=$(${GH:-gh} api "repos/$repo/actions/runs/$id/jobs") || unknown "job list for run $id failed"
  hit=$(jq -r --arg j "$job" '.jobs[] | select(.name == $j and .status == "in_progress") | .name' <<<"$jobs") ||
    unknown "job list for run $id unreadable"
  [ -z "$hit" ] || { echo "busy: $wf run $id job $hit"; exit 1; }
done
echo free
