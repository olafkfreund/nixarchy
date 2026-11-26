#!/usr/bin/env bash
set -euo pipefail

table='nightly.yml|0 3 * * *|-||
omarchy.yml|0 4 * * *|-||
update.yml|0 5 * * *|-||
review.yml|0 6 * * *|-||nightly.yml,omarchy.yml,update.yml
omarchy-edge.yml|0 6 * * *|-||
flake-update.yml|0 7 * * *|-||
build.yml|0 6 * * 1|-|push|
weekly.yml|0 9 * * 0|stable-session||
weekly.yml|0 15 * * 0|install-stock-iso||
weekly.yml|0 6 * * 1|propose||nightly.yml'

if [[ ${1:-} == --table && $# == 1 ]]; then
  while IFS='|' read -r workflow cron input extra waits; do
    printf '%s\t%s\t%s\n' "$workflow" "$cron" "$input"
  done <<< "$table"
  exit 0
fi
if [[ $# -gt 1 || ( $# == 1 && $1 != --dry-run ) ]]; then
  echo 'usage: schedule-watchdog.sh [--dry-run|--table]' >&2
  exit 2
fi

export TZ=UTC GH_REPO=olafkfreund/nixarchy GITHUB_REPOSITORY=olafkfreund/nixarchy
now=${NOW:-$(date -u +%s)}
[[ $now =~ ^[0-9]+$ ]] || { echo "invalid NOW: $now" >&2; exit 2; }
gh=${GH:-gh}
state=${STATE:-${XDG_STATE_HOME:-$HOME/.local/state}}
vm_host_free=${VM_HOST_FREE:-$(dirname "$0")/vm-host-free.sh}
declare -A runs=() failed=()
error=0 dispatched=0

slot_for() {
  local cron=$1 minute hour day today weekday slot delta
  if [[ $cron =~ ^([0-9]{1,2})\ ([0-9]{1,2})\ \*\ \*\ (\*|[0-6])$ ]]; then
    minute=${BASH_REMATCH[1]} hour=${BASH_REMATCH[2]} day=${BASH_REMATCH[3]}
  else
    echo "unsupported cron: $cron" >&2
    return 1
  fi
  if (( 10#$minute > 59 || 10#$hour > 23 )); then
    echo "invalid cron: $cron" >&2
    return 1
  fi
  today=$(date -u -d "@$now" +%F)
  slot=$(date -u -d "$today $hour:$minute:00" +%s) || return 1
  if [[ $day == '*' ]]; then
    (( slot <= now )) || slot=$((slot - 86400))
  else
    weekday=$(date -u -d "@$now" +%w)
    delta=$(( (weekday - day + 7) % 7 ))
    slot=$((slot - delta * 86400))
    (( slot <= now )) || slot=$((slot - 7 * 86400))
  fi
  printf '%s\n' "$slot"
}

read_runs() {
  local workflow=$1 reply
  [[ ! -v failed[$workflow] ]] || return 1
  if [[ ! -v runs[$workflow] ]]; then
    if ! reply=$("$gh" api "repos/olafkfreund/nixarchy/actions/workflows/$workflow/runs?branch=main&per_page=50"); then
      echo "failed to read runs: $workflow" >&2
      failed[$workflow]=1 error=1
      return 1
    fi
    if ! jq -e '.workflow_runs | type == "array"' >/dev/null <<< "$reply"; then
      echo "invalid runs: $workflow" >&2
      failed[$workflow]=1 error=1
      return 1
    fi
    runs[$workflow]=$reply
  fi
}

in_flight() {
  jq -e '[.workflow_runs[] | select(.head_branch == "main" and .status != "completed")] | length > 0' >/dev/null <<< "${runs[$1]}"
}

qualifies() {
  local workflow=$1 slot=$2 input=$3 extra=$4 ids id reply
  read_runs "$workflow" || return 2
  ids=$(jq -r --argjson slot "$slot" --arg extra "$extra" '
    .workflow_runs[] | select(.head_branch == "main" and
      (.event == "schedule" or .event == "workflow_dispatch" or (.event == $extra and $extra != "")) and
      .conclusion != "cancelled" and (.created_at | fromdateiso8601) >= $slot) | .id
  ' <<< "${runs[$workflow]}") || { failed[$workflow]=1; error=1; return 2; }
  [[ -n $ids ]] || return 1
  [[ $input != - ]] && {
    while IFS= read -r id; do
      if ! reply=$("$gh" api "repos/olafkfreund/nixarchy/actions/runs/$id/jobs"); then
        echo "failed to read jobs: $workflow run $id" >&2
        failed[$workflow]=1 error=1
        return 2
      fi
      if ! jq -e '.jobs | type == "array"' >/dev/null <<< "$reply"; then
        echo "invalid jobs: $workflow run $id" >&2
        failed[$workflow]=1 error=1
        return 2
      fi
      if jq -e --arg input "$input" '[.jobs[] | select(.name == $input and .conclusion != "skipped" and .status != "skipped")] | length > 0' >/dev/null <<< "$reply"; then
        return 0
      fi
    done <<< "$ids"
    return 1
  }
  return 0
}

while IFS='|' read -r workflow cron input extra waits; do
  if ! slot=$(slot_for "$cron"); then error=1; continue; fi
  label="$workflow $input"
  if (( now - slot < 2700 )); then echo "$label: not due"; continue; fi
  if (( now - slot > 86400 )); then echo "$label: too old"; continue; fi
  # GitHub's schedule can arrive hours late rather than never (9-11 h on
  # 2026-11-25), so a slot we dispatched gets its late run cancelled. Not
  # weekly: with delays that long, a run's time cannot say which job it is.
  if [[ $input == - && -e "$state/schedule-watchdog/${workflow}---${slot}" ]] && read_runs "$workflow"; then
    late=$(jq -r --argjson slot "$slot" '.workflow_runs[] | select(.head_branch == "main" and
      .event == "schedule" and .status != "completed" and (.created_at | fromdateiso8601) >= $slot) | .id' <<< "${runs[$workflow]}")
    for id in $late; do
      if [[ ${1:-} == --dry-run ]]; then echo "$label: would cancel late run $id"; continue; fi
      if "$gh" api -X POST "repos/olafkfreund/nixarchy/actions/runs/$id/cancel" >/dev/null; then
        echo "$label: cancelled late run $id"
      else
        echo "cancel failed: $label run $id" >&2; error=1
      fi
    done
  fi
  if qualifies "$workflow" "$slot" "$input" "$extra"; then
    echo "$label: done"; continue
  else
    rc=$?
    if (( rc == 2 )); then echo "$label: unreadable"; continue; fi
  fi
  if in_flight "$workflow"; then echo "$label: in flight"; continue; fi
  blocked=0
  if [[ -n $waits ]]; then
    IFS=, read -r -a prerequisites <<< "$waits"
    for prerequisite in "${prerequisites[@]}"; do
      # A prerequisite's cron is its own row's, so the table is the only list.
      prerequisite_cron=$(awk -F'|' -v w="$prerequisite" '$1 == w { print $2; exit }' <<< "$table")
      if ! prerequisite_slot=$(slot_for "$prerequisite_cron"); then
        error=1 blocked=1; break
      fi
      if qualifies "$prerequisite" "$prerequisite_slot" - ''; then
        if in_flight "$prerequisite"; then blocked=1; break; fi
      else
        blocked=1; break
      fi
    done
  fi
  if (( blocked )); then echo "$label: waiting"; continue; fi
  if [[ $workflow == nightly.yml ]]; then
    if ! install_state=$(bash "$vm_host_free" install) || [[ $install_state != free ]] ||
       ! edge_state=$(bash "$vm_host_free" edge) || [[ $edge_state != free ]]; then
      echo "$label: VM host busy"; continue
    fi
  fi
  marker="$state/schedule-watchdog/${workflow}-${input}-${slot}"
  if [[ -e $marker ]]; then echo "$label: already dispatched"; continue; fi
  if ! reply=$("$gh" api "repos/olafkfreund/nixarchy/actions/workflows/$workflow/runs?branch=main&per_page=50"); then
    echo "failed to re-read runs: $workflow" >&2; failed[$workflow]=1 error=1; continue
  fi
  if ! jq -e '.workflow_runs | type == "array"' >/dev/null <<< "$reply"; then
    echo "invalid re-read: $workflow" >&2; failed[$workflow]=1 error=1; continue
  fi
  runs[$workflow]=$reply
  if in_flight "$workflow"; then echo "$label: in flight"; continue; fi
  if [[ ${1:-} == --dry-run ]]; then echo "$label: would dispatch"; continue; fi
  args=(workflow run "$workflow" --ref main)
  [[ $input == - ]] || args+=(-f "job=$input")
  if ! "$gh" "${args[@]}"; then echo "dispatch failed: $label" >&2; error=1; continue; fi
  mkdir -p "$(dirname "$marker")"
  touch "$marker"
  echo "$label: dispatched"
  dispatched=1
done <<< "$table"

if (( dispatched )); then notify-send 'Nixarchy schedule watchdog' 'Dispatched missed workflows' || true; fi
exit "$error"
