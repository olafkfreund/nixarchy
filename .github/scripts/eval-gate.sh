#!/usr/bin/env bash
# Does every output we cache, and every pin-fix probe, still evaluate? (#1459)
#
#   eval-gate.sh [--batch-only]        run from the repo root
#
# stdout is an interface: one `target<TAB>message` row per failing target.
# Everything else goes to stderr. Exit 0: all evaluate. Exit 1: failures
# (rows on stdout; none with --batch-only). Exit 2: infrastructure -- the
# allowlist or table failed or came back empty, or the batch failed but no
# single target could be confirmed failing. Callers must not turn 2 into an
# "upstream broke it" report.
# Why: docs/internals/workflows.md (flake-update.yml). Capture lists with
# out=$(cmd) || exit 2, never mapfile < <(cmd): AGENTS.md section 4.
set -uo pipefail

batch_only=0
[ "${1:-}" = "--batch-only" ] && batch_only=1

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

allow=$("$here/cache-allowlist.sh") || { echo "eval-gate: cache-allowlist.sh failed" >&2; exit 2; }
probes=$(nix eval --json --no-eval-cache -f data/pin-fix.nix --apply 't: builtins.attrValues (builtins.mapAttrs (_: v: v.probe) t)' | jq -r '.[]') ||
  { echo "eval-gate: cannot read data/pin-fix.nix" >&2; exit 2; }
[ -n "$allow" ] || { echo "eval-gate: empty allowlist" >&2; exit 2; }
[ -n "$probes" ] || { echo "eval-gate: empty probe table" >&2; exit 2; }

targets=()
declare -A seen=()
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in .#*) ;; *) t=".#$t" ;; esac
  [ -z "${seen[$t]:-}" ] || continue
  seen[$t]=1
  targets+=("$t")
done < <(printf '%s\n%s\n' "$allow" "$probes")

pi() { nix path-info --derivation --no-eval-cache "$@"; }

echo "eval-gate: ${#targets[@]} targets, batch" >&2
if pi "${targets[@]}" >/dev/null; then exit 0; fi
[ "$batch_only" = 1 ] && exit 1

[ -z "${EVAL_GATE_LOG_DIR:-}" ] || mkdir -p "$EVAL_GATE_LOG_DIR"
failed=0
for t in "${targets[@]}"; do
  err=$(pi "$t" 2>&1 >/dev/null) && continue
  failed=1
  [ -z "${EVAL_GATE_LOG_DIR:-}" ] || printf '%s\n' "$err" >"$EVAL_GATE_LOG_DIR/$(printf '%s' "$t" | tr '/#' '__').log"
  msg=$(printf '%s\n' "$err" | sed 's/\x1b\[[0-9;]*[A-Za-z]//g' |
    awk '/^[ \t]*error:/ { blk = "" } { blk = blk " " $0 } END { print blk }' |
    tr -s ' \t' ' ' | sed 's/^ //' | cut -c1-300)
  printf '%s\t%s\n' "$t" "$msg"
done
[ "$failed" = 1 ] && exit 1
echo "eval-gate: batch failed but no single target does" >&2
exit 2
