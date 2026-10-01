#!/usr/bin/env bash
set -euo pipefail

first_run=$1 cleanup=$2 verifier=$3 bash_bin=$4 real_rm=$5 real_stat=$6 bin_path=$7
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"
printf '#!%s\n' "$bash_bin" >"$test_root/bin/systemctl"
cat >>"$test_root/bin/systemctl" <<'STUB'
printf '%s\n' "$*" >>"$TEST_LOG"
if [[ " $* " == *' show '* ]]; then
  [[ ${TEST_SYSTEMCTL_FAIL:-0} == 1 ]] && exit 1
  printf 'LoadState=%s\nFragmentPath=%s\n' "$TEST_LOAD" "$TEST_FRAGMENT"
elif [[ " $* " == *' is-active '* ]]; then
  exit "${TEST_ACTIVE:-1}"
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
printf '#!%s\n' "$bash_bin" >"$test_root/bin/stat"
cat >>"$test_root/bin/stat" <<'STUB'
if [[ ${TEST_STAT_MISMATCH:-} && " $* " == *"$TEST_STAT_MISMATCH"* ]]; then
  printf '%s\n' 99999
else
  exec "$REAL_STAT" "$@"
fi
STUB
chmod +x "$test_root/bin/stat"
export REAL_RM=$real_rm REAL_STAT=$real_stat TEST_LOG=$test_root/systemctl.log
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
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$alice_units/omarchy-sleep-lock.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$alice_units/graphical-session.target.wants/omarchy-sleep-lock.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-recover-internal-monitor.service/omarchy-recover-internal-monitor.service \
  "$alice_units/graphical-session-pre.target.wants/omarchy-recover-internal-monitor.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-crash-watch.service/omarchy-crash-watch.service \
  "$alice_units/graphical-session.target.wants/omarchy-crash-watch.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-fcitx5.service/omarchy-fcitx5.service \
  "$alice_units/omarchy-fcitx5.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-fcitx5.service/omarchy-fcitx5.service \
  "$alice_units/graphical-session.target.wants/omarchy-fcitx5.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-bt-agent.service/bt-agent.service "$alice_units/bt-agent.service"
printf '%s\n' 'my unit' >"$bob_units/omarchy-sleep-lock.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-foreign.service/omarchy-sleep-lock.service \
  "$bob_units/graphical-session.target.wants/omarchy-sleep-lock.service"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-home-manager-generation/home-files/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-unit-omarchy-crash-watch.service/omarchy-crash-watch.service \
  "$bob_units/omarchy-crash-watch.service"
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
for link in \
  "$alice_units/graphical-session.target.wants/omarchy-crash-watch.service" \
  "$alice_units/omarchy-fcitx5.service" \
  "$alice_units/graphical-session.target.wants/omarchy-fcitx5.service"; do
  test ! -L "$link" || { echo "old unit link survived cleanup: $link" >&2; exit 1; }
done
test "$(cat "$bob_units/omarchy-sleep-lock.service")" = 'my unit' || {
  echo 'cleanup changed a user-owned unit' >&2; exit 1;
}
test -L "$bob_units/graphical-session.target.wants/omarchy-sleep-lock.service" || {
  echo 'cleanup removed a foreign unit link' >&2; exit 1;
}
test -L "$bob_units/omarchy-crash-watch.service" || {
  echo 'cleanup removed a Home Manager-shaped unit link' >&2; exit 1;
}
echo 'Cleanup removes generated links outside /home and preserves user-owned units'

fail_home=$test_root/fail-home
mkdir -p "$fail_home/.config/systemd/user"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-crash-watch.service/omarchy-crash-watch.service \
  "$fail_home/.config/systemd/user/omarchy-crash-watch.service"
FAIL_RM_PATTERN=fail-home bash "$cleanup" "$fail_home" >"$test_root/failure.out" 2>&1
test -L "$fail_home/.config/systemd/user/omarchy-crash-watch.service"
grep -F 'could not remove old user unit link' "$test_root/failure.out" >/dev/null
echo 'A failed link removal warns without failing activation'

owner_home=$test_root/owner-home
mkdir -p "$owner_home/.config/systemd/user"
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
  "$owner_home/.config/systemd/user/omarchy-sleep-lock.service"
TEST_STAT_MISMATCH=omarchy-sleep-lock.service bash "$cleanup" "$owner_home" >"$test_root/owner.out" 2>&1
test -L "$owner_home/.config/systemd/user/omarchy-sleep-lock.service" || {
  echo 'cleanup removed a link owned by another user' >&2; exit 1;
}
grep -F 'refusing link owned by another user' "$test_root/owner.out" >/dev/null
echo 'Cleanup refuses a generated-looking link owned by another user'

sed -n '/^check_nixarchy_user_unit() {/,/^}/p' "$verifier" >"$test_root/verify-function.sh"
test -s "$test_root/verify-function.sh"
bad() { printf 'BAD %s\n' "$1"; }
hmm() { printf 'NOTE %s\n' "$1"; }
maybe_bad() {
  if [ "$omarchy_here" = 1 ]; then bad "$@"; else hmm "$@"; fi
}
source "$test_root/verify-function.sh"
omarchy_here=1
export HOME=$test_root/verify TEST_LOAD=not-found TEST_FRAGMENT=
mkdir -p "$HOME/.config/systemd/user"
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'BAD omarchy-sleep-lock cannot load'* ]] || {
  echo 'verifier did not fail a missing sleep-lock unit' >&2; exit 1;
}
omarchy_here=0
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'NOTE omarchy-sleep-lock cannot load'* && $got != *BAD* ]] || {
  echo 'verifier failed a machine without Omarchy' >&2; exit 1;
}
omarchy_here=1
export TEST_SYSTEMCTL_FAIL=1
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'BAD omarchy-sleep-lock state is unavailable'* ]] || {
  echo 'verifier ignored a failed systemctl show' >&2; exit 1;
}
unset TEST_SYSTEMCTL_FAIL
export TEST_LOAD=masked TEST_FRAGMENT=/etc/systemd/user/omarchy-sleep-lock.service
got=$(check_nixarchy_user_unit omarchy-sleep-lock)
[[ $got == *'BAD omarchy-sleep-lock cannot load (masked)'* ]] || {
  echo 'verifier accepted a masked sleep-lock unit' >&2; exit 1;
}
export TEST_LOAD=loaded TEST_FRAGMENT=/etc/systemd/user/omarchy-sleep-lock.service
ln -s /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-unit-omarchy-sleep-lock.service/omarchy-sleep-lock.service \
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
sed -n '/^if systemctl --user is-active omarchy-sleep-lock.service/,/^fi$/p' "$verifier" >"$test_root/active-check.sh"
test -s "$test_root/active-check.sh"
ok() { printf 'OK %s\n' "$1"; }
omarchy_here=0
got=$(source "$test_root/active-check.sh")
[[ $got == *'NOTE nothing locks before suspend'* ]] || {
  echo 'inactive sleep-lock was fatal without Omarchy' >&2; exit 1;
}
omarchy_here=1
got=$(source "$test_root/active-check.sh")
[[ $got == *'BAD nothing locks before suspend'* ]] || {
  echo 'inactive sleep-lock stopped being fatal with Omarchy' >&2; exit 1;
}
echo 'Verifier distinguishes missing, unavailable, masked, shadowed, and user-owned units'
echo 'Omarchy-absent unit failures remain notes; active-state check remains fatal with Omarchy'

gate=$test_root/fcitx-gate.sh
gate_unit=$test_root/etc/systemd/user/omarchy-fcitx5.service
sed -n '/^for unit in omarchy-sleep-lock omarchy-crash-watch omarchy-recover-internal-monitor/,/^fi$/p' "$verifier" |
  sed "s#/etc/systemd/user/omarchy-fcitx5.service#$gate_unit#" >"$gate"
test -s "$gate"
TEST_CALLED=$test_root/called
check_nixarchy_user_unit() { printf '%s\n' "$1" >>"$TEST_CALLED"; }
: >"$TEST_CALLED"
source "$gate"
if grep -Fx 'omarchy-fcitx5' "$TEST_CALLED" >/dev/null; then
  echo 'fcitx5 verifier ran without the declared unit' >&2; exit 1;
fi
mkdir -p "$(dirname "$gate_unit")"
: >"$gate_unit"
: >"$TEST_CALLED"
source "$gate"
grep -Fx 'omarchy-fcitx5' "$TEST_CALLED" >/dev/null || {
  echo 'fcitx5 verifier skipped an installed unit' >&2; exit 1;
}
echo 'Fcitx5 verification follows the installed unit, not session variables'
