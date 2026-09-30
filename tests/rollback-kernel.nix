{ pkgs, script }:
pkgs.runCommand "nixarchy-rollback-kernel"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.util-linux
    ];
  }
  ''
    set -euo pipefail
    fail() { echo "FAIL: $1" >&2; exit 1; }

    mkdir -p stubs
    printf '%s\n' '#!/bin/sh' 'cat "$CASE_ROOT/gens.json"' > stubs/nixos-rebuild
    printf '%s\n' '#!/bin/sh' 'case "$1" in choose) head -1 ;; confirm) echo confirm >> "$CASE_ROOT/events"; exit 1 ;; esac' > stubs/gum
    printf '%s\n' '#!/bin/sh' 'echo sudo >> "$CASE_ROOT/events"; exit 1' > stubs/sudo
    printf '%s\n' '#!/bin/sh' 'exit 0' > stubs/nvd
    chmod +x stubs/*

    touch kernel-a kernel-b modules-a modules-b
    root=$PWD
    warning='Kernel or kernel modules for generation 1 differ from the booted system or could not be verified.'

    run_case() {
      name=$1 target_kernel=$2 target_modules=$3 boot_kernel=$4 boot_modules=$5 expected=$6
      case_root=$root/$name
      mkdir -p "$case_root/profile/system-1-link" "$case_root/booted"
      printf '%s\n' '[{"generation":1,"date":"d","nixosVersion":"v","kernelVersion":"6.1.0","current":false},{"generation":2,"date":"d","nixosVersion":"v","kernelVersion":"6.1.0","current":true}]' > "$case_root/gens.json"
      ln -s "$root/$target_kernel" "$case_root/profile/system-1-link/kernel"
      ln -s "$root/$target_modules" "$case_root/profile/system-1-link/kernel-modules"
      ln -s "$root/$boot_kernel" "$case_root/booted/kernel"
      ln -s "$root/$boot_modules" "$case_root/booted/kernel-modules"
      cp ${script} "$case_root/rollback"
      sed -i \
        -e "s|^profile=/nix/var/nix/profiles/system|profile=$case_root/profile/system|" \
        -e "s|/run/booted-system|$case_root/booted|g" \
        "$case_root/rollback"
      CASE_ROOT="$case_root" PATH="$root/stubs:$PATH" bash "$case_root/rollback" </dev/null > "$case_root/output" 2>&1 || fail "$name: rollback exited nonzero"
      grep -qx confirm "$case_root/events" || fail "$name: confirmation was not reached exactly once"
      ! grep -qF sudo "$case_root/events" || fail "$name: a system switch was attempted"
      if [ "$expected" = warn ]; then
        grep -Fq "$warning" "$case_root/output" || fail "$name: missing reboot warning"
        awk -v warning="$warning" '$0 ~ warning { w = NR } /What changes:/ { d = NR } END { exit !(w && d && w < d) }' "$case_root/output" || fail "$name: warning followed the diff"
      else
        ! grep -Fq "$warning" "$case_root/output" || fail "$name: warned for identical kernel and modules"
      fi
      echo "rollback $name: $expected"
    }

    run_case same-version-kernel kernel-b modules-a kernel-a modules-a warn
    run_case module-only kernel-a modules-b kernel-a modules-a warn
    run_case unresolved kernel-a missing-modules kernel-a modules-a warn
    run_case identical kernel-a modules-a kernel-a modules-a quiet
    touch "$out"
  ''
