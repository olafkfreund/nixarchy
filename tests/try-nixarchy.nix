{ pkgs, vmTargetMiB }:
# installer/try-nixarchy.sh, on the machines it will actually meet.
#
# The script exists for somebody on Ubuntu or Fedora with no nix, so almost
# everything it does is refuse: no qemu, no UEFI firmware, not enough memory, a
# disk left by a previous run, an image that does not match the release's
# checksum. Those refusals ARE the script -- the qemu line at the end is four
# lines -- and a refusal nobody has watched fire is a refusal nobody knows
# works.
#
# checks.try-preflight does the same job for the `nix run …#try` front door.
# This is its counterpart for the front door that has no nix behind it.
#
# Runs in seconds: no VM is started. The happy path ends in a qemu window,
# which no sandbox has, so what is asserted here is everything up to it.
let
  script = ../installer/try-nixarchy.sh;
in
pkgs.runCommand "nixarchy-try-nixarchy"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.shellcheck
    ];
  }
  ''
    export HOME=$PWD
    cp ${script} ./try-nixarchy.sh
    chmod +x ./try-nixarchy.sh
    fail=0

    # ---- it is valid shell ------------------------------------------------
    # First, because every assertion below is worthless against a script that
    # does not parse.
    # Invoked as `bash ./try-nixarchy.sh` throughout, never as ./try-nixarchy.sh:
    # the sandbox has no /usr/bin/env, so the shebang -- which is right for the
    # Ubuntu and Fedora machines this script is FOR -- cannot resolve here.
    shellcheck ./try-nixarchy.sh || { echo "shellcheck rejected it" >&2; fail=1; }
    echo "  shellcheck clean"

    read_number() {
      local name=$1 file=$2 pattern=$3 value
      value=$(sed -n "s/$pattern/\\1/p" "$file" | head -1) || exit 1
      if ! [[ $value =~ ^[0-9]+$ ]]; then
        echo "could not read $name from $file" >&2
        exit 1
      fi
      printf '%s\n' "$value"
    }
    install_min=$(read_number MIN_DISK_GIB ${../installer/install.sh} '^MIN_DISK_GIB=\([0-9][0-9]*\)$')
    launcher_default=$(read_number NIXARCHY_TRY_DISK ./try-nixarchy.sh '^DISK_GB=''${NIXARCHY_TRY_DISK:-\([0-9][0-9]*\)}$')
    launcher_min=$(read_number MIN_DISK_GB ./try-nixarchy.sh '^MIN_DISK_GB=\([0-9][0-9]*\)$')
    try_mib=$(read_number DISK_MB ${../installer/try.sh} '^DISK_MB=\([0-9][0-9]*\)$')
    vm_mib=${toString vmTargetMiB}
    [[ $vm_mib =~ ^[0-9]+$ ]] || { echo 'could not read emptyDiskImages size from installer/vm.nix' >&2; exit 1; }
    [ "$launcher_default" -eq 64 ] || { echo 'try-nixarchy.sh default must be 64 GB' >&2; exit 1; }
    [ "$launcher_min" -eq "$install_min" ] || { echo 'try-nixarchy.sh MIN_DISK_GB differs from install.sh MIN_DISK_GIB' >&2; exit 1; }
    [ "$try_mib" -ge "$((install_min * 1024))" ] || { echo 'try.sh DISK_MB is under install.sh MIN_DISK_GIB' >&2; exit 1; }
    [ "$vm_mib" -ge "$((install_min * 1024))" ] || { echo 'installer/vm.nix emptyDiskImages is under install.sh MIN_DISK_GIB' >&2; exit 1; }

    res=$(bash ./try-nixarchy.sh --full 2>&1 || true)
    case "$res" in
      *"full image is gone"*"network image"*) echo "  --full explains the network image" ;;
      *) echo "--full did not explain that the full image is gone" >&2; fail=1 ;;
    esac

    # ---- a missing tool names the package, per distribution ---------------
    # "install qemu" is not one command anywhere, and somebody who has to go
    # and search for it is somebody who stops here.
    res=$(PATH=/nonexistent ${pkgs.bash}/bin/bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"apt install"*"dnf install"*"pacman -S"*) echo "  a missing tool names all four" ;;
      *) echo "a missing tool did not name the distribution packages" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # ---- no UEFI firmware -------------------------------------------------
    # UEFI-only is not negotiable: the installer writes systemd-boot to an ESP,
    # so a BIOS machine has nothing to find.
    stub=$PWD/stub; mkdir -p "$stub"
    for b in qemu-system-x86_64 qemu-img curl; do
      printf '#!/bin/sh\nexit 0\n' > "$stub/$b"; chmod +x "$stub/$b"
    done
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$PWD/qemu-args"\n' > "$stub/qemu-system-x86_64"
    chmod +x "$stub/qemu-system-x86_64"
    printf '#!/bin/sh\nif [ "$1" = info ]; then\n  if [ -f "$PWD/info-24" ]; then\n    echo "virtual size: 24 GiB (25769803776 bytes)"\n    exit 0\n  fi\n  exit 1\nfi\nexit 0\n' > "$stub/qemu-img"
    chmod +x "$stub/qemu-img"
    patchShebangs "$stub" >/dev/null
    export PATH="$stub:$PATH"

    res=$(NIXARCHY_TRY_DIR=$PWD/w1 bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"No UEFI firmware"*) echo "  missing OVMF refuses" ;;
      *) echo "a machine with no OVMF did not refuse" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac
    # A sandbox has no nix on PATH, which is exactly the branch a Debian user
    # takes: name the package for each distribution.
    case "$res" in
      *"apt install ovmf"*) echo "  and names the package per distribution" ;;
      *) echo "the OVMF refusal did not name the packages" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # The other branch, and the one worth having: somebody who HAS nix should
    # be sent to `nix run …#try`, not told to `apt install ovmf` -- useless
    # advice on the single distribution with a better answer. Reached with a
    # stub, because a sandbox has no nix of its own.
    printf '#!/bin/sh\nexit 0\n' > "$stub/nix"; chmod +x "$stub/nix"
    patchShebangs "$stub/nix" >/dev/null
    res=$(NIXARCHY_TRY_DIR=$PWD/w1b bash ./try-nixarchy.sh 2>&1 || true)
    rm -f "$stub/nix"
    case "$res" in
      *"nix run github:"*) echo "  and points a nix user at #try instead" ;;
      *) echo "did not offer #try to somebody who has nix" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # Firmware from here on, so the later refusals are reachable at all.
    : > "$PWD/code.fd"; : > "$PWD/vars.fd"
    export NIXARCHY_TRY_OVMF_CODE=$PWD/code.fd NIXARCHY_TRY_OVMF_VARS=$PWD/vars.fd

    # ---- more memory than the machine has ---------------------------------
    # Named with BOTH numbers and a flag that would work. A refusal that says
    # only "not enough memory" leaves somebody guessing what would do.
    res=$(NIXARCHY_TRY_DIR=$PWD/w2 bash ./try-nixarchy.sh --memory 999999999 2>&1 || true)
    case "$res" in
      *"this machine has"*"--memory "*) echo "  too much memory refuses with both numbers" ;;
      *) echo "the memory refusal did not name the numbers" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # ---- a disk left by a previous run ------------------------------------
    # Never silently reused and never silently wiped: it holds an install
    # somebody may have spent twenty minutes on.
    mkdir -p "$PWD/w3"; : > "$PWD/w3/nixarchy-try.qcow2"
    res=$(NIXARCHY_TRY_DIR=$PWD/w3 bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"already exists"*"--boot"*"--fresh"*) echo "  an existing disk offers both ways out" ;;
      *) echo "an existing disk was not handled" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    : > "$PWD/info-24"
    res=$(NIXARCHY_TRY_DIR=$PWD/w3 bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"is 24 GB, under the installer's 32 GB minimum"*"--boot"*"--fresh"*) echo "  a small existing disk names its size and both ways out" ;;
      *) echo "a small existing disk did not name its size" >&2; fail=1 ;;
    esac
    rm -f "$PWD/info-24"
    res=$(NIXARCHY_TRY_DIR=$PWD/w3 NIXARCHY_TRY_DISK=24 bash ./try-nixarchy.sh --fresh 2>&1 || true)
    case "$res" in
      *"NIXARCHY_TRY_DISK=24 is under the installer's 32 GB minimum"*) echo "  --fresh refuses a small requested disk" ;;
      *) echo "--fresh accepted a small requested disk" >&2; fail=1 ;;
    esac
    [ -f "$PWD/w3/nixarchy-try.qcow2" ] || { echo '--fresh removed the disk before refusing' >&2; fail=1; }
    res=$(NIXARCHY_TRY_DIR=$PWD/w3 NIXARCHY_TRY_DISK=not-a-number bash ./try-nixarchy.sh --fresh 2>&1 || true)
    case "$res" in
      *"NIXARCHY_TRY_DISK=not-a-number must be a whole number"*) echo "  --fresh refuses a non-integer disk size" ;;
      *) echo "--fresh accepted a non-integer disk size" >&2; fail=1 ;;
    esac
    [ -f "$PWD/w3/nixarchy-try.qcow2" ] || { echo 'non-integer --fresh removed the disk' >&2; fail=1; }

    res=$(NIXARCHY_TRY_DIR=$PWD/w4 bash ./try-nixarchy.sh --boot 2>&1 || true)
    case "$res" in
      *"to boot"*) echo "  --boot with no disk refuses" ;;
      *) echo "--boot with no disk did not refuse" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # ---- an image that is not what the release published -------------------
    # The one refusal with a security argument behind it, and the one that was
    # briefly right by accident: `sha256sum -c | grep "$iso"` matches the
    # FAILED line as happily as the OK one, and refused only because pipefail
    # carried sha256sum's status out of the pipe. Both directions are asserted
    # here so that a rewrite cannot quietly start accepting a bad image.
    mkdir -p "$PWD/w5"
    printf 'not an iso' > "$PWD/w5/nixarchy-vTEST-net.iso"
    printf '%s  nixarchy-vTEST-net.iso\n' "$(printf 0123456789abcdef | sha256sum | cut -d' ' -f1)" \
      > "$PWD/w5/SHA256SUMS"
    printf '#!/bin/sh\necho \x27{ "tag_name": "vTEST" }\x27\n' > "$stub/curl"
    chmod +x "$stub/curl"
    patchShebangs "$stub/curl" >/dev/null

    res=$(NIXARCHY_TRY_DIR=$PWD/w5 bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"does not match the published checksum"*) echo "  a corrupt image refuses" ;;
      *) echo "a corrupt image was NOT refused -- this is the one that matters" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
    esac

    # And the same file with a checksum that genuinely matches must get past it.
    printf '%s  nixarchy-vTEST-net.iso\n' "$(sha256sum "$PWD/w5/nixarchy-vTEST-net.iso" | cut -d' ' -f1)" \
      > "$PWD/w5/SHA256SUMS"
    res=$(NIXARCHY_TRY_DIR=$PWD/w5 bash ./try-nixarchy.sh 2>&1 || true)
    case "$res" in
      *"does not match the published checksum"*)
        echo "a MATCHING image was refused; the check tests the wrong thing" >&2; printf %s\\n "$res" | sed "s/^/    | /" >&2; fail=1 ;;
      *) echo "  a matching image passes" ;;
    esac
    grep -Fx 'virtio-blk-pci,drive=target,serial=nixarchy-try-no-nix' qemu-args >/dev/null || {
      echo "no-Nix try launched without a target-disk serial" >&2; fail=1;
    }

    [ "$fail" = 0 ] || { echo "try-nixarchy.sh does not refuse the way it claims" >&2; exit 1; }
    echo "the no-nix front door refuses in sentences"
    touch $out
  ''
