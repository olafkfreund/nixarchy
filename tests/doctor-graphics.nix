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

  # NO driver at all -- and this stub is why the branch for it was broken.
  #
  # The other two stubs print only what a SUCCEEDING vainfo prints, so they
  # never reproduced the preamble real vainfo writes to STDOUT before it opens
  # anything, and keeps writing when va_openDriver() fails. Measured against
  # the pinned binary the doctor runs:
  #
  #   LIBVA_DRIVER_NAME=nosuchdrv vainfo 2>/dev/null
  #   -> "Trying display: wayland", exit 3
  #
  # With no fixture for it, `[ -z "$va" ]` looked correct and could never fire
  # on a real machine: $va always held that line. The no-driver branch was
  # untested AND unreachable, so a machine with no VAAPI at all was told
  # "decode only" and pointed at nvidia-vaapi-driver. A stub that omits the
  # preamble is a stub that agrees with the bug.
  printf '#!/bin/sh\necho "Trying display: wayland"\nexit 3\n' > fix/bin/vainfo-none

  # NVIDIA alone, to catch Intel advice on a machine with no Intel in it.
  mk fix/nvidia "0000:01:00.0" 0x10de

  chmod +x fix/bin/vainfo fix/bin/vainfo-enc fix/bin/vainfo-none

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
  # The section named a VAAPI driver and never named the GPU: `dgpu` is set
  # only for 0x10de, so every AMD and Intel machine without an NVIDIA card
  # fell past both the hybrid and the discrete branch in silence.
  want    "a single GPU is named"    "$a" 'Single AMD GPU'

  # No driver answered -- the branch that could not fire.
  n=$(run amd vainfo-none)
  want    "no driver is said so"     "$n" 'No VAAPI driver answered'
  # And is NOT mistaken for a driver that merely cannot encode, which is what
  # this machine was told before: a wrong diagnosis, plus advice about
  # nvidia-vaapi-driver it does not have.
  wantnot "not called decode-only"   "$n" 'cannot encode'

  # Intel advice belongs on Intel machines. Matched on the SNIPPET LINE, not on
  # the string: the notes mention intel-media-driver in prose on purpose
  # ("on Intel that is usually...") and that prose is fine to read on any
  # machine. What was wrong is a paste-in line installing a package for
  # hardware that is not there -- a first draft of this assertion forbade the
  # bare string and failed against correctly-gated code, which would have sent
  # someone deleting the explanation instead of the snippet.
  nv=$(run nvidia vainfo-none)
  wantnot "no intel snippet on nvidia" "$nv" 'extraPackages.*intel-media-driver'
  nvd=$(run nvidia vainfo)
  wantnot "none on decode-only nvidia" "$nvd" 'extraPackages.*intel-media-driver'
  # ...and it is still offered where it helps, so the gate did not simply
  # delete the advice.
  i=$(run hybrid vainfo-none)
  want    "intel snippet on intel"    "$i" 'extraPackages.*intel-media-driver'

  [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
  echo "the doctor reads a GPU correctly"
  touch $out
''
