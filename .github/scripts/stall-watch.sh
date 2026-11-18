#!/usr/bin/env bash
# shellcheck disable=SC2016 # Child shells expand these single-quoted commands.
set -Eeuo pipefail

# Read a stall as lock (a blocked /proc/locks waiter in the nix tree), download
# (a nix-owned socket with recent traffic and no builder), build (a builder child
# with a growing log), or unclassified. Only the deadline changes job status (124).

if [[ ${1:-} != run || $# -lt 5 || ${4:-} != -- ]]; then
  echo 'usage: stall-watch.sh run <seconds> <log> -- <cmd...>' >&2
  exit 2
fi

seconds=$2
log=$3
shift 4

snapshot() {
  echo '::group::omarchy-stall'
  printf 'deadline: %ss; JOB_T0: %s\n' "$deadline" "${JOB_T0:-unset}"
  echo '== process forest =='
  timeout 10 ps -eo pid,ppid,etime,stat,wchan:20,args --forest 2>&1 || true
  echo '== /proc/locks =='
  timeout 10 cat /proc/locks 2>&1 || true
  echo '== sockets =='
  timeout 10 ss -tnpi 2>&1 || true
  echo '== nix fds =='
  timeout 10 bash -c 'ps -C nix,nix-daemon -o pid= | while read -r p; do echo "/proc/$p/fd"; ls -l "/proc/$p/fd"; done' 2>&1 || true
  echo '== disk/mem =='
  timeout 10 df -h /nix 2>&1 || true
  timeout 10 free -m 2>&1 || true
  echo '== nix-daemon journal =='
  timeout 10 journalctl -u nix-daemon -n 50 --no-pager 2>&1 || true
  echo '== recent builder logs =='
  timeout 10 bash -c 'find "${NIX_LOG_DIR:-/nix/var/log/nix}/drvs" -type f -printf "%T@ %p\n" | sort -nr | head -10 | cut -d" " -f2- | while read -r f; do echo "--- $f"; case $f in *.bz2) bzcat -- "$f" | tail -n 10 ;; *) tail -n 10 -- "$f" ;; esac; done' 2>&1 || true
  echo '== log tail =='
  timeout 10 tail -n 30 -- "$log" 2>&1 || true
  echo '::endgroup::'
}

deadline=$seconds
if [[ -n ${JOB_T0:-} ]]; then
  remaining=$((3600 - $(date +%s) + JOB_T0 - 300))
  (( remaining < deadline )) && deadline=$remaining
fi

setsid bash -c 'set -o pipefail; "$@" 2>&1 | tee -- "$0"' "$log" "$@" &
pid=$!
started=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  if (( $(date +%s) - started >= deadline )); then
    snapshot | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
    echo "::error title=omarchy-stall::$1 exceeded ${deadline}s (requested ${seconds}s)" || true
    kill -TERM -- "-$pid" 2>/dev/null || true
    for ((i = 0; i < 10; i++)); do
      kill -0 -- "-$pid" 2>/dev/null || break
      sleep 1 || true
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 124
  fi
  sleep 1
done
rc=0
wait "$pid" || rc=$?
exit "$rc"
