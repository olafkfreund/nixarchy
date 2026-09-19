#!/usr/bin/env bash
set -euo pipefail
vm=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_STATE_HOME="$work/state"
export MUTATION_STATE="$work/unit-state"
mkdir -p "$HOME" "$XDG_STATE_HOME/nixarchy/microvm"
state="$XDG_STATE_HOME/nixarchy/microvm"
fail=0

# Never reach the host's user manager or start a real VM from this check.
systemctl() { if [ -f "$MUTATION_STATE" ]; then echo activating; else echo inactive; fi; }
nix() { echo 'unexpected build' >&2; return 99; }
systemd-run() { echo 'unexpected detached launch' >&2; return 99; }
export -f systemctl nix systemd-run

# A name accepted by create is accepted everywhere, and traversal is refused
# before constructing a path. Each iteration gets disposable parent state.
for op in create run console set-template stop rm; do
  for name in . .. ../outside 'bad/name'; do
    mkdir -p "$state" "$XDG_STATE_HOME/nixarchy/outside"
    printf 'unchanged\n' > "$XDG_STATE_HOME/nixarchy/template"
    args=("$op" "$name")
    [ "$op" != set-template ] || args+=(shell)
    if "$vm" "${args[@]}" > "$work/error" 2>&1 ||
      ! grep -q 'name must be' "$work/error"; then
      echo "FAIL: $op accepted or failed to validate '$name'" >&2
      fail=1
    fi
    if [ "$(cat "$XDG_STATE_HOME/nixarchy/template" 2>/dev/null || true)" != unchanged ]; then
      echo "FAIL: $op changed the parent directory" >&2
      fail=1
    fi
  done
done
mkdir -p "$state"
"$vm" create safe-name_1 >/dev/null
for template in '.*' 'shell$' $'shell\npersistent'; do
  if "$vm" create bad-template --template "$template" > "$work/error" 2>&1; then
    echo "FAIL: create accepted literal nonexistent template '$template'" >&2
    fail=1
    rm -rf "$state/bad-template"
  fi
  if "$vm" set-template safe-name_1 "$template" > "$work/error" 2>&1; then
    echo "FAIL: set-template accepted literal nonexistent template '$template'" >&2
    fail=1
  fi
done

# Model the deterministic handoff: the old inactive observation expires as
# the lock is acquired. A post-lock unit check must refuse every mutator.
flock() {
  command flock "$@" || return
  touch "$MUTATION_STATE"
}
export -f flock
for op in rm set-template run detach; do
  rm -f "$MUTATION_STATE"
  "$vm" create "race-$op" >/dev/null
  case "$op" in
    detach) args=(run --detach "race-$op") ;;
    set-template) args=(set-template "race-$op" persistent) ;;
    *) args=("$op" "race-$op") ;;
  esac
  if "$vm" "${args[@]}" > "$work/error" 2>&1 ||
    ! grep -q 'running' "$work/error" ||
    [ ! -f "$MUTATION_STATE" ] ||
    [ "$(cat "$state/race-$op/template" 2>/dev/null || true)" != shell ]; then
    echo "FAIL: $op did not refuse the unit becoming active at lock acquisition" >&2
    fail=1
  fi
done
# The prebuilt runner is the active unit: it must still accept the handoff.
"$vm" create prebuilt >/dev/null
mkdir -p "$state/prebuilt/current/bin"
printf '#!%s\nexit 0\n' "$(command -v bash)" > "$state/prebuilt/current/bin/microvm-run"
chmod +x "$state/prebuilt/current/bin/microvm-run"
if ! "$vm" run --prebuilt prebuilt; then
  echo 'FAIL: the prebuilt runner refused its own active unit' >&2
  fail=1
fi
[ "$fail" -eq 0 ]
echo 'VM name validation, literal templates and post-lock unit checks passed'
