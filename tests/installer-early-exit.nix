{ pkgs, renderedInstallScript }:
# Drive the packaged installer's main() with a pty. The keyboard and account
# questions, hardware guard and destructive phases are stubbed; the real
# greeter, disk_rows, ask_device, exit trap, dashboard and failure screen run.
pkgs.runCommand "nixarchy-installer-early-exit"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      gawk
      util-linux
    ];
  }
  ''
    rendered=${renderedInstallScript}
    # The rendered package is sourced so the harness can replace the UEFI
    # hardware guard and later destructive phases before calling real main().
    # Its build-time @ui@ and @gumenv@ substitutions are already in place.
    sed -e "s@/run/nixarchy-install@$PWD/probe-run@g" \
        -e "s@/var/log/nixarchy-install.log@$PWD/probe.log@g" \
        "$rendered" > rendered-install
    chmod +x rendered-install
    printf '%s\n' \
      'set -euo pipefail' \
      '. "$PWD/rendered-install"' \
      'PATH="$PWD/stub:$PATH"' \
      'require_root_and_uefi() { :; }' \
      'function [ {' \
      '  if builtin [ "$PROBE_ANSWERS" = 1 ] && builtin [ "$1" = -b ] && builtin [ "$2" = "$PWD/tiny" ]; then return 0; fi' \
      '  builtin [ "$@"' \
      '}' \
      'ask_keymap() { :; }' \
      'ask_identity() { :; }' \
      'if [ "$PROBE_BOUNDARY" = 1 ]; then' \
      '  ask_device() { :; }' \
      '  ask_disk_mode() { :; }' \
      '  ask_encrypt() { :; }' \
      '  confirm_summary() { :; }' \
      '  write_flake() { :; }' \
      '  replace_missing_disk() { :; }' \
      '  confirm_repo_disks() { :; }' \
      '  preflight_build() { :; }' \
      '  format_disk() { return 7; }' \
      'fi' \
      'main "$@"' > harness.sh

    mkdir -p stub
    printf '#!${pkgs.runtimeShell}\ncase "$1 $2" in\n  "-dnpo NAME,TYPE") printf "%%s\\n" "$PWD/tiny disk" ;;\n  "-bdno SIZE") printf "25769803776\\n" ;;\n  "-dno SIZE") printf "24G\\n" ;;\n  "-dno MODEL") printf "TEST\\n" ;;\n  "-dnro RM,TRAN") printf "0 sata\\n" ;;\n  "-dno TYPE") printf "disk\\n" ;;\n  *) exit 1 ;;\nesac\n' > stub/lsblk
    printf '#!${pkgs.runtimeShell}\nexit 1\n' > stub/findmnt
    printf '#!${pkgs.runtimeShell}\ncase "$*" in *"config show substituters"*) exit 0 ;; esac\nexit 1\n' > stub/nix
    printf '#!${pkgs.runtimeShell}\nexit 1\n' > stub/gum
    printf '#!${pkgs.runtimeShell}\nexit 0\n' > stub/bash
    chmod +x stub/*
    patchShebangs stub >/dev/null
    PATH="$PWD/stub:$PATH"
    export PATH PROBE_BOUNDARY PROBE_ANSWERS
    PROBE_BOUNDARY=0
    PROBE_ANSWERS=0

    # script supplies a pty to the installer. The first Return clears the
    # greeter; the second clears the hold before the shell stub exits.
    printf '\n\n' | script -qec '${pkgs.bash}/bin/bash harness.sh' /dev/null > interactive.out 2>&1 || true
    grep -q 'no disk large enough to install onto' interactive.out
    grep -q 'The installer stopped before writing to any disk.' interactive.out
    grep -q 'Press Return for a root shell.' interactive.out

    ${pkgs.bash}/bin/bash harness.sh </dev/null > no-tty.out 2>&1 || true
    grep -q 'no disk large enough to install onto' no-tty.out
    if grep -q 'Press Return for a root shell.' no-tty.out; then echo 'installer-early-exit: FAIL no-tty.out showed the hold prompt' >&2; exit 1; fi

    # The answers file names a block device whose stubbed size is 24 GiB.
    # This goes through validate_answers, not ask_device.
    : > tiny
    printf '%s\n' \
      "device=$PWD/tiny" 'encrypt=no' 'hostname=probe' 'username=probe' \
      'password_hash=$6$probe' 'timezone=UTC' 'keymap=us' > answers
    PROBE_ANSWERS=1 ${pkgs.bash}/bin/bash harness.sh --answers "$PWD/answers" </dev/null > answers.out 2>&1 || true
    grep -q 'device: .* is under 32 GiB' answers.out
    if grep -q 'Press Return for a root shell.' answers.out; then echo 'installer-early-exit: FAIL answers.out showed the hold prompt' >&2; exit 1; fi

    PROBE_BOUNDARY=1
    printf '\n' | script -qec '${pkgs.bash}/bin/bash harness.sh' /dev/null > dashboard.out 2>&1 || true
    grep -q 'nixarchy installation stopped' dashboard.out
    if grep -q 'Press Return for a root shell.' dashboard.out; then echo 'installer-early-exit: FAIL dashboard.out showed the hold prompt' >&2; exit 1; fi
    touch "$out"
  ''
