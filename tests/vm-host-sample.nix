{ pkgs, ... }:
pkgs.runCommand "nixarchy-vm-host-sample"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
    ];
  }
  ''
    script=${../.github/scripts/vm-host-sample.sh}
    fail() { echo "FAIL: $*" >&2; exit 1; }
    mkdir -p empty bin
    export GITHUB_JOB=sample-test
    export GITHUB_STEP_SUMMARY=$PWD/summary

    # A /proc of known values: the runner cannot see qemu (ProtectProc=invisible), so the
    # sample carries host pressure instead (#1858), and this pins every field.
    mkdir -p fake/pressure
    echo '9.50 8.25 7.00 3/1989 4242' > fake/loadavg
    printf '%s\n' 'MemTotal: 263000000 kB' 'MemAvailable: 204800 kB' > fake/meminfo
    printf '%s\n' 'some avg10=12.34 avg60=1.00 avg300=0.50 total=1' 'full avg10=1.00 avg60=0.00 avg300=0.00 total=1' > fake/pressure/cpu
    printf '%s\n' 'some avg10=5.67 avg60=1.00 avg300=0.50 total=1' 'full avg10=2.00 avg60=0.00 avg300=0.00 total=1' > fake/pressure/io
    VM_HOST_PROC=$PWD/fake bash "$script" 1000 -- true > case1
    [ "$(grep -c '^vm-host:' case1)" = 2 ] || fail 'case 1: expected first and last samples'
    [ "$(grep -c '^vm-host:' summary)" = 2 ] || fail 'case 1: summary samples missing'
    [ "$(grep -Ec '^vm-host: t=[0-9]+ load=9.50 8.25 7.00 mem_avail=200M cpu=12.34 io=5.67 job=sample-test$' case1)" = 2 ] || fail "case 1: wrong sample: $(cat case1)"

    rc=0
    bash "$script" 1000 -- bash -c 'exit 7' > case2 || rc=$?
    [ "$rc" = 7 ] || fail 'wrapper swallowed exit status'

    rc=0
    VM_HOST_PROC=$PWD/empty bash "$script" 1000 -- bash -c 'exit 7' > case3 || rc=$?
    [ "$rc" = 7 ] || fail 'case 3: wrapper changed exit status'
    [ "$(grep -Fc 'load=? mem_avail=?M cpu=? io=? job=sample-test' case3)" = 2 ] || fail 'case 3: missing-field fallback absent'

    unset GITHUB_STEP_SUMMARY
    bash "$script" 1000 -- true > case4 || fail 'case 4: unset summary failed'

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo "$$" >> "$sleep_pids"' 'exec ${pkgs.coreutils}/bin/sleep "$@"' > bin/sleep
    chmod +x bin/sleep
    export sleep_pids=$PWD/sleep-pids
    PATH="$PWD/bin:$PATH" bash "$script" 1 -- ${pkgs.coreutils}/bin/sleep 2 > case5
    [ -s "$sleep_pids" ] || fail 'case 5: sampler sleep did not start'
    while read -r pid; do
      if kill -0 "$pid" 2>/dev/null; then fail "orphaned sleep $pid"; fi
    done < "$sleep_pids"

    bash "$script" 1000 -- true > case6
    count=$(grep -c '^vm-host:' case6) || :
    [ "$count" = 2 ] || fail "expected 2 vm-host lines, got $count"
    touch "$out"
  ''
