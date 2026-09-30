#!/usr/bin/env bash
set -euo pipefail

script=$1
bash_bin=$2
runtime_path=$3
TEST_ROOT=$(mktemp -d)
export TEST_ROOT
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir "$TEST_ROOT/bin"

printf '#!%s\n' "$bash_bin" >"$TEST_ROOT/bin/bt-agent"
cat >>"$TEST_ROOT/bin/bt-agent" <<'EOF'
printf '%s\n' "$$" >"$TEST_ROOT/agent.pid"
trap 'touch "$TEST_ROOT/agent.stopped"; exit 0' TERM
printf '%s\n' 'Agent registered'
if [[ ${TEST_READY:-1} == 1 ]]; then printf '%s\n' 'Default agent requested'; fi
while true; do sleep 0.1; done
EOF

printf '#!%s\n' "$bash_bin" >"$TEST_ROOT/bin/bluetoothctl"
cat >>"$TEST_ROOT/bin/bluetoothctl" <<'EOF'
case $1 in
  show) printf '\tPowered: yes\n\tPairable: %s\n' "$(if [[ ${TEST_PAIRABLE:-1} == 1 ]]; then echo yes; else echo no; fi)" ;;
  pair|trust|connect|disconnect|remove)
    printf '%s\n' "$1" >>"$TEST_ROOT/actions"
    if [[ $1 == connect && -e "$TEST_ROOT/agent.pid" && ! -e "$TEST_ROOT/agent.stopped" ]]; then
      touch "$TEST_ROOT/connect-before-agent-stop"
    fi
    if [[ $1 == pair && ${TEST_PAIR_BLOCK:-0} == 1 ]]; then sleep 1; fi
    ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$TEST_ROOT/bin/bt-agent" "$TEST_ROOT/bin/bluetoothctl"
export PATH="$TEST_ROOT/bin:$runtime_path"
address=00:11:22:33:44:55

"$script" pair "$address"
test -e "$TEST_ROOT/agent.stopped" || { echo 'pair left its agent running' >&2; exit 1; }
test ! -e "$TEST_ROOT/connect-before-agent-stop" || {
  echo 'connect ran before the temporary agent stopped' >&2; exit 1;
}
test "$(cat "$TEST_ROOT/actions")" = $'pair\ntrust\nconnect' || {
  echo 'pair/trust/connect sequence changed' >&2; exit 1;
}

rm "$TEST_ROOT/agent.pid" "$TEST_ROOT/agent.stopped" "$TEST_ROOT/actions"
for action in connect disconnect forget; do "$script" "$action" "$address"; done
test ! -e "$TEST_ROOT/agent.pid" || { echo 'non-pair action started an agent' >&2; exit 1; }

rm "$TEST_ROOT/actions"
if TEST_READY=0 "$script" pair "$address" >"$TEST_ROOT/failure.log" 2>&1; then
  echo 'pair continued without a registered agent' >&2
  exit 1
fi
test -e "$TEST_ROOT/agent.stopped" || { echo 'failed pair left its agent running' >&2; exit 1; }
test ! -e "$TEST_ROOT/actions" || { echo 'pairing ran without a registered agent' >&2; exit 1; }
grep -Fq 'did not register' "$TEST_ROOT/failure.log" || {
  echo 'failed registration gave no useful error' >&2; exit 1;
}

rm "$TEST_ROOT/agent.pid" "$TEST_ROOT/agent.stopped"
if TEST_PAIRABLE=0 "$script" pair "$address" >"$TEST_ROOT/not-pairable.log" 2>&1; then
  echo 'pair continued while the adapter was not pairable' >&2
  exit 1
fi
test -e "$TEST_ROOT/agent.stopped" || { echo 'non-pairable failure left its agent running' >&2; exit 1; }
test ! -e "$TEST_ROOT/actions" || { echo 'pairing ran while the adapter was not pairable' >&2; exit 1; }
grep -Fq 'did not become pairable' "$TEST_ROOT/not-pairable.log" || {
  echo 'non-pairable adapter gave no useful error' >&2; exit 1;
}

rm "$TEST_ROOT/agent.pid" "$TEST_ROOT/agent.stopped"
TEST_PAIR_BLOCK=1 "$script" pair "$address" >"$TEST_ROOT/interrupted.log" 2>&1 &
pair_pid=$!
for attempt in {1..50}; do
  test -e "$TEST_ROOT/actions" && break
  sleep 0.1
done
test -e "$TEST_ROOT/actions" || { echo 'pair did not start before interruption' >&2; exit 1; }
kill -TERM "$pair_pid"
wait "$pair_pid" 2>/dev/null || true
test -e "$TEST_ROOT/agent.stopped" || { echo 'interrupted pair left its agent running' >&2; exit 1; }

echo 'Bluetooth pair agent stops before connect and refuses an unpairable adapter'
