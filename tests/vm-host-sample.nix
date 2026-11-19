{ pkgs, ... }:
pkgs.runCommand "nixarchy-vm-host-sample"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      procps
    ];
  }
  ''
    script=${../.github/scripts/vm-host-sample.sh}
    fail() { echo "FAIL: $*" >&2; exit 1; }
    mkdir -p empty bin
    export GITHUB_JOB=sample-test
    export GITHUB_STEP_SUMMARY=$PWD/summary

    bash "$script" 1000 -- true > case1
    [ "$(grep -c '^vm-host:' case1)" = 2 ] || fail 'case 1: expected first and last samples'
    [ "$(grep -c '^vm-host:' summary)" = 2 ] || fail 'case 1: summary samples missing'
    [ "$(grep -Ec '^vm-host: t=[0-9]+ load=[0-9.]+ [0-9.]+ [0-9.]+ mem_avail=[0-9]+M qemu=[0-9]+ job=sample-test$' case1)" = 2 ] || fail 'case 1: malformed sample'

    rc=0
    bash "$script" 1000 -- bash -c 'exit 7' > case2 || rc=$?
    [ "$rc" = 7 ] || fail 'wrapper swallowed exit status'

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 127' > bin/pgrep
    chmod +x bin/pgrep
    rc=0
    VM_HOST_PROC=$PWD/empty PATH="$PWD/bin:$PATH" bash "$script" 1000 -- bash -c 'exit 7' > case3 || rc=$?
    [ "$rc" = 7 ] || fail 'case 3: wrapper changed exit status'
    [ "$(grep -Fc 'load=? mem_avail=?M qemu=? job=sample-test' case3)" = 2 ] || fail 'case 3: missing-field fallback absent'

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'echo 0' 'exit 1' > bin/pgrep
    PATH="$PWD/bin:$PATH" bash "$script" 1000 -- true > case7
    [ "$(grep -Fc 'qemu=0 job=sample-test' case7)" = 2 ] || fail 'case 7: no-match count lost'

    unset GITHUB_STEP_SUMMARY
    bash "$script" 1000 -- true > case4 || fail 'case 4: unset summary failed'

    rm bin/pgrep
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
