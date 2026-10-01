{ pkgs, ... }:
pkgs.runCommand "nixarchy-verify-boxes"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
    ];
  }
  ''
      set -euo pipefail
      output_path=$out
      source_file=${../pkgs/verify.sh}
      section=$TMPDIR/boxes.sh
      test "$(grep -c '^# ---- boxes ' "$source_file")" -eq 1 || { echo 'FAIL: Boxes section marker missing'; exit 1; }
      test "$(grep -c '^# ---- summary ' "$source_file")" -eq 1 || { echo 'FAIL: summary section marker missing'; exit 1; }
      sed -n '/^# ---- boxes /,/^# ---- summary /{ /^# ---- boxes /d; /^# ---- summary /d; p; }' "$source_file" > "$section"
      grep -Fq 'distrobox enter "$box"' "$section" || { echo 'FAIL: Boxes section extraction missed enter'; exit 1; }

      export HOME=$TMPDIR/home
      mkdir -p "$HOME/.local/share/applications"
      calls=$TMPDIR/calls
      scenario=mixed
    head_() { :; }
    ok() { :; }
    hmm() { printf 'NOTE: %s\n' "$1"; }
    bad() { fail=$((fail + 1)); printf 'BAD: %s\n' "$1"; }
    say_dim() { printf '%s\n' "$1"; }
    grep() {
      last=
      quiet=0
      for arg in "$@"; do
        last=$arg
        if [[ $arg == -q ]]; then quiet=1; fi
      done
      case "$last" in
        /etc/subuid|/etc/subgid)
          if (( quiet )); then return 0; fi
          printf '%s:100000:65536\n' "$(id -un)"
          ;;
        *) command grep "$@" ;;
      esac
    }
    timeout() { shift; "$@"; }
      distrobox() { printf 'enter %s\n' "$2" >> "$calls"; }
      podman() {
        case "$1" in
          info) return 0 ;;
          inspect)
            for arg in "$@"; do name=$arg; done
            printf 'inspect %s\n' "$name" >> "$calls"
            printf '/run/current-system/sw/bin/distrobox\n'
            ;;
          ps)
            all=0
            labeled=0
            for arg in "$@"; do
              case "$arg" in
                -a) all=1 ;;
                label=manager=distrobox) labeled=1 ;;
              esac
            done
            if [[ $scenario == fail-all && $all == 1 ]] || [[ $scenario == fail-running && $all == 0 ]]; then
              echo 'stub listing failed' >&2
              return 2
            fi
            printf 'running\n'
            if (( all )); then printf 'stopped\n'; fi
            if (( ! labeled )); then printf 'ordinary\n'; fi
            ;;
          *) echo "unexpected podman call: $*" >&2; return 2 ;;
        esac
      }

      run_case() {
        scenario=$1
        fail=0
        : > "$calls"
        source "$section" > "$TMPDIR/$scenario.log"
      }

      run_case mixed
      test "$fail" -eq 0 || { echo 'FAIL: mixed selection reported a false failure'; cat "$TMPDIR/mixed.log"; exit 1; }
      grep -Fxq 'enter running' "$calls" || { echo 'FAIL: running Distrobox was not entered'; exit 1; }
      grep -Fxq 'inspect running' "$calls" || { echo 'FAIL: running Distrobox was not inspected'; exit 1; }
      if grep -Eq '^(enter|inspect) (stopped|ordinary)$' "$calls"; then
        echo 'FAIL: stopped or ordinary container reached Distrobox verification'
        cat "$calls"
        exit 1
      fi
      grep -Fq '1 stopped Distrobox container' "$TMPDIR/mixed.log" || { echo 'FAIL: skipped-box count missing'; exit 1; }
      if grep -Fq ordinary "$TMPDIR/mixed.log"; then echo 'FAIL: ordinary container reported as a box'; exit 1; fi
      echo 'running Distrobox selected; stopped and ordinary containers skipped'

      for failure in fail-all fail-running; do
        run_case "$failure"
        test "$fail" -gt 0 || { echo "FAIL: $failure listing error was hidden"; exit 1; }
        test ! -s "$calls" || { echo "FAIL: $failure listing error still entered a box"; cat "$calls"; exit 1; }
      done
      echo 'Podman listing errors fail closed without entering a box'
      touch "$output_path"
  ''
