#!/usr/bin/env bash
set -euo pipefail

first_run=$1 cleanup=$2 verifier=$3 bash_bin=$4 real_rm=$5 bin_path=$6
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"
printf '#!%s\n' "$bash_bin" >"$test_root/bin/systemctl"
cat >>"$test_root/bin/systemctl" <<'STUB'
printf '%s\n' "$*" >>"$TEST_LOG"
if [[ " $* " == *' show '* ]]; then
  printf 'LoadState=%s\nFragmentPath=%s\n' "$TEST_LOAD" "$TEST_FRAGMENT"
fi
STUB
chmod +x "$test_root/bin/systemctl"
printf '#!%s\n' "$bash_bin" >"$test_root/bin/rm"
cat >>"$test_root/bin/rm" <<'STUB'
if [[ ${FAIL_RM_PATTERN:-} && " $* " == *"$FAIL_RM_PATTERN"* ]]; then
  exit 1
fi
exec "$REAL_RM" "$@"
STUB
chmod +x "$test_root/bin/rm"
export REAL_RM=$real_rm TEST_LOG=$test_root/systemctl.log
export PATH=$test_root/bin:$bin_path

bash "$first_run"
test ! -e "$TEST_LOG" || {
  echo 'first-run called systemctl instead of relying on wantedBy' >&2; exit 1;
}
echo 'First-run makes no user-unit systemctl call'

alice="$test_root/srv/alice's home"
bob=$test_root/srv/bob
for home in "$alice" "$bob"; do
  mkdir -p "$home/.config/systemd/user/graphical-session.target.wants" \
    "$home/.config/systemd/user/graphical-session-pre.target.wants"
done
alice_units=$alice/.config/systemd/user
bob_units=$bob/.config/systemd/user
ln -s /nix/store/abc-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$alice_units/omarchy-sleep-lock.service"
ln -s /nix/store/abc-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$alice_units/graphical-session.target.wants/omarchy-sleep-lock.service"
ln -s /nix/store/abc-unit-omarchy-recover-internal-monitor.service/omarchy-recover-internal-monitor.service \
  "$alice_units/graphical-session-pre.target.wants/omarchy-recover-internal-monitor.service"
ln -s /nix/store/abc-unit-bt-agent.service/bt-agent.service "$alice_units/bt-agent.service"
printf '%s\n' 'my unit' >"$bob_units/omarchy-sleep-lock.service"
ln -s /nix/store/abc-unit-foreign.service/omarchy-sleep-lock.service \
  "$bob_units/graphical-session.target.wants/omarchy-sleep-lock.service"
bash "$cleanup" "$alice" "$bob" >"$test_root/cleanup.out"
test ! -L "$alice_units/omarchy-sleep-lock.service" || {
  echo 'old sleep-lock unit link survived cleanup' >&2; exit 1;
}
test ! -L "$alice_units/graphical-session.target.wants/omarchy-sleep-lock.service" || {
  echo 'old sleep-lock wants link survived cleanup' >&2; exit 1;
}
test ! -L "$alice_units/graphical-session-pre.target.wants/omarchy-recover-internal-monitor.service" || {
  echo 'old monitor recovery wants link survived cleanup' >&2; exit 1;
}
test ! -L "$alice_units/bt-agent.service" || {
  echo 'old Bluetooth unit link survived cleanup' >&2; exit 1;
}
test "$(cat "$bob_units/omarchy-sleep-lock.service")" = 'my unit' || {
  echo 'cleanup changed a user-owned unit' >&2; exit 1;
}
test -L "$bob_units/graphical-session.target.wants/omarchy-sleep-lock.service" || {
  echo 'cleanup removed a foreign unit link' >&2; exit 1;
}
echo 'Cleanup removes generated links outside /home and preserves user-owned units'

fail_home=$test_root/fail-home
mkdir -p "$fail_home/.config/systemd/user"
ln -s /nix/store/abc-unit-omarchy-crash-watch.service/omarchy-crash-watch.service \
  "$fail_home/.config/systemd/user/omarchy-crash-watch.service"
FAIL_RM_PATTERN=fail-home bash "$cleanup" "$fail_home" >"$test_root/failure.out" 2>&1
test -L "$fail_home/.config/systemd/user/omarchy-crash-watch.service"
grep -F 'could not remove old user unit link' "$test_root/failure.out" >/dev/null
echo 'A failed link removal warns without failing activation'

sed -n '/^check_nixarchy_user_unit() {/,/^}/p' "$verifier" >"$test_root/verify-function.sh"
test -s "$test_root/verify-function.sh"
bad() { printf 'BAD %s\n' "$1"; }
hmm() { printf 'NOTE %s\n' "$1"; }
source "$test_root/verify-function.sh"
export HOME=$test_root/verify TEST_LOAD=not-found TEST_FRAGMENT=
mkdir -p "$HOME/.config/systemd/user"
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'BAD omarchy-sleep-lock cannot load'* ]] || {
  echo 'verifier did not fail a missing sleep-lock unit' >&2; exit 1;
}
export TEST_LOAD=loaded TEST_FRAGMENT=/etc/systemd/user/omarchy-sleep-lock.service
ln -s /nix/store/abc-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$HOME/.config/systemd/user/omarchy-sleep-lock.service"
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'BAD omarchy-sleep-lock is shadowed'* ]] || {
  echo 'verifier did not fail a stale shadowing link' >&2; exit 1;
}
rm "$HOME/.config/systemd/user/omarchy-sleep-lock.service"
printf '%s\n' 'user override' >"$HOME/.config/systemd/user/omarchy-sleep-lock.service"
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'NOTE omarchy-sleep-lock has a user override'* ]] || {
  echo 'verifier did not distinguish a user-owned override' >&2; exit 1;
}
echo 'Verifier distinguishes missing, stale-shadowed, and user-owned units'
