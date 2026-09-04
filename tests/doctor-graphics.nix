{ pkgs, doctor }:
# The doctor's Graphics section, driven against fixture machines.
#
# checks.install's VM runs llvmpipe and has no PCI display controller at all,
# so it can never reach any branch of this. The rules would be untested in a
# repo full of tests, which is the shape that let #251 ship broken and green.
#
# So: a fake /sys/bus/pci (NIXARCHY_SYSFS_PCI) and a stub vainfo on PATH. Both
# are the only inputs the section has, which is why it was written to take them
# from one variable and one command rather than from lspci.
#
# The fixtures are real. The decode-only vainfo is the shape a reporter's
# NVIDIA laptop actually printed -- eighteen profiles, every one VLD -- and the
# hybrid addresses are an ordinary Intel iGPU at 00:02.0 with a dGPU at 01:00.0.
pkgs.runCommand "nixarchy-doctor-graphics" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  mk() { mkdir -p "$1/$2"; echo 0x030000 > "$1/$2/class"; echo "$3" > "$1/$2/vendor"; }
  mkdir -p fix/bin
  mk fix/hybrid "0000:00:02.0" 0x8086
  mk fix/hybrid "0000:01:00.0" 0x10de
  mk fix/amd    "0000:e3:00.0" 0x1002

  # Decode only: a driver that opens, returns 0, and cannot record a thing.
  printf '#!/bin/sh\necho "vainfo: Driver version: VA-API NVDEC driver"\necho "  VAProfileH264Main : VAEntrypointVLD"\n' > fix/bin/vainfo
  # And one that can.
  printf '#!/bin/sh\necho "vainfo: Driver version: Mesa Gallium radeonsi"\necho "  VAProfileH264Main : VAEntrypointEncSlice"\n' > fix/bin/vainfo-enc
  chmod +x fix/bin/vainfo fix/bin/vainfo-enc

  # HOME and USER because the doctor reads ~/.config and names the user in its
  # snippet, and a build sandbox has neither -- without them it dies on line 24
  # under `set -u` and prints nothing at all, which reads exactly like a rule
  # that found nothing. That cost a debugging round; it is what the empty-output
  # guard below is for.
  export HOME=$PWD/home USER=tester
  mkdir -p "$HOME"

  run() { # run <sysfs> <vainfo> [LIBVA_DRIVER_NAME]
    ( export NIXARCHY_VAINFO="$PWD/fix/bin/$2" NIXARCHY_SYSFS_PCI="$PWD/fix/$1"
      # export, not a `VAR=val cmd` prefix built by expansion: a word coming out
      # of ''${3:+...} is a COMMAND to bash, not an assignment, and it failed with
      # "LIBVA_DRIVER_NAME=nvidia: command not found".
      # `if`, not `&&`: the builder runs under `set -e`, so a test that is false
      # is a non-zero last status and kills the subshell before the doctor runs.
      # The case with no third argument produced no output at all because of it.
      if [ -n "''${3-}" ]; then export LIBVA_DRIVER_NAME="$3"; fi
      ${doctor}/bin/nixarchy-doctor 2>&1 ) || true
  }

  fails=0
  want() { # want <name> <output> <pattern>
    if printf '%s' "$2" | grep -q "$3"; then echo "  ok      $1"
    else echo "  FAILED  $1: no /$3/ in the output"; fails=$((fails + 1)); fi
  }
  wantnot() {
    if printf '%s' "$2" | grep -q "$3"; then
      echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
    else echo "  ok      $1"; fi
  }

  h=$(run hybrid vainfo nvidia)
  # Every `want` below fails identically when the doctor produced nothing, which
  # is indistinguishable from every rule being wrong. Say which it is.
  printf '%s' "$h" | grep -q 'Graphics' || {
    echo "the doctor printed no Graphics section at all:"; printf '%s\n' "$h"; exit 1; }
  want "hybrid is detected"          "$h" 'Hybrid graphics'
  want "decode-only driver is named" "$h" 'cannot encode'
  want "the libva pin is named"      "$h" 'pinning libva'
  # The conversion is the load-bearing arithmetic: sysfs and lspci print these
  # in hex, Nix wants decimal, and nixos-gpu/SKILL.md flags it as a trap. A
  # wrong answer here is a machine that will not start a desktop.
  want "intel bus id, hex->decimal"  "$h" 'intelBusId = "PCI:0:2:0"'
  want "nvidia bus id, hex->decimal" "$h" 'nvidiaBusId = "PCI:1:0:0"'
  # offload is written; sync is offered, never chosen for them.
  want "offload is written"          "$h" 'offload.enable = true'
  want "sync is offered as a choice" "$h" 'prime.sync.enable'

  a=$(run amd vainfo-enc)
  want    "encode is recognised"     "$a" 'Video encoding available'
  wantnot "single GPU is not hybrid" "$a" 'Hybrid graphics'
  # e3 is the case that makes the conversion undeniable: read as decimal it is
  # nonsense, and this machine really has a GPU there.
  wantnot "no prime for one GPU"     "$a" 'nvidiaBusId'

  [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
  echo "the doctor reads a GPU correctly"
  touch $out
''
