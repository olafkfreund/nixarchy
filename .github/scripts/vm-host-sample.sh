#!/usr/bin/env bash
set -uo pipefail

if [ "$#" -lt 3 ] || [ "$2" != -- ]; then
  echo 'usage: vm-host-sample.sh <interval> -- <command...>' >&2
  exit 2
fi
i=$1
shift 2
proc=${VM_HOST_PROC:-/proc}
start=$SECONDS

sample() {
  load=$( { read -r a b c _ < "$proc/loadavg" && printf '%s %s %s' "$a" "$b" "$c"; } 2>/dev/null) || load='?'
  mem=$( { while read -r key value _; do
    if [ "$key" = MemAvailable: ]; then printf '%s' "$((value / 1024))"; break; fi
  done < "$proc/meminfo"; } 2>/dev/null) || mem='?'
  [ -n "$mem" ] || mem='?'
  qemu=$(pgrep -c qemu-system 2>/dev/null) || :
  [ -n "$qemu" ] || qemu='?'
  line="vm-host: t=$((SECONDS - start)) load=$load mem_avail=${mem}M qemu=$qemu job=${GITHUB_JOB:-?}"
  printf '%s\n' "$line"
  printf '%s\n' "$line" >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || :
}

sample
(
  trap 'kill "$s" 2>/dev/null; wait "$s" 2>/dev/null; exit 0' TERM
  while :; do
    sleep "$i" & s=$!
    wait "$s"
    sample
  done
) 2>/dev/null &
sampler=$!
trap 'kill "$sampler" 2>/dev/null; wait "$sampler" 2>/dev/null' EXIT
"$@"
rc=$?
sample
exit "$rc"
