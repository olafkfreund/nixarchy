{ pkgs, ... }:
# Quattro's after-sleep SDDM recovery, as shipped here (#1905): our unit-name
# patch and the restart decision, against stub systemctl and loginctl with the
# real awk. Upstream's own test covers its logic against sddm.service; this
# covers the script NixOS actually runs.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-sddm-recover"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    script=${shipped}/share/omarchy/bin/omarchy-system-sddm-recover
    if [ ! -e "$script" ]; then
      echo "sddm-recover: skipped, this pin ships no omarchy-system-sddm-recover"
      touch $out
      exit 0
    fi

    mkdir fake-bin
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      'printf "%s\n" "$*" >> "$CALLS"' \
      '[ "$1" != is-active ] || [ "$DM_ACTIVE" = 1 ]' > fake-bin/systemctl
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[ "$LOGIN_FAIL" != 1 ] || exit 1' \
      'printf "%s" "$SESSIONS"' > fake-bin/loginctl
    chmod +x fake-bin/systemctl fake-bin/loginctl
    export PATH=$PWD/fake-bin:$PATH CALLS=$PWD/calls

    seated=$(printf '%s\n' \
      '     2 1000 omarchy seat0 1234 user    tty2 no -' \
      '     3 1000 omarchy -     1240 manager -    no -')
    seatless=$(printf '%s\n' \
      '     3 1000 omarchy -     1240 manager -    no -' \
      '     7    0 root    -     2001 user    -    no -')

    check() {
      name=$1 want=$2
      : > "$CALLS"
      rc=0
      bash "$script" > output 2>&1 || rc=$?
      got=$(grep -cx 'restart --no-block display-manager.service' "$CALLS" || true)
      if [ "$rc" -ne 0 ] || [ "$got" -ne "$want" ]; then
        echo "FAILED $name: exit $rc (want 0), restarts $got (want $want)" >&2
        cat output "$CALLS" >&2
        exit 1
      fi
      echo "PASS $name: restarts $got"
    }

    DM_ACTIVE=1 LOGIN_FAIL=0 SESSIONS=$seated check 'a seat session is left alone' 0
    DM_ACTIVE=1 LOGIN_FAIL=0 SESSIONS=$seatless check 'no seat session restarts the display manager' 1
    DM_ACTIVE=0 LOGIN_FAIL=0 SESSIONS=$seatless check 'an inactive display manager is left alone' 0
    DM_ACTIVE=1 LOGIN_FAIL=1 SESSIONS=$seatless check 'a failed logind query is left alone' 0

    if grep -q 'sddm\.service' "$script"; then
      echo "FAILED: the shipped script still names sddm.service, which NixOS does not have" >&2
      exit 1
    fi
    echo "PASS the shipped script names display-manager.service only"
    touch $out
  ''
