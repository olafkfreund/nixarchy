{ inputs, pkgs, ... }:
# installer/hardware-modules.sh, driven against fixture machines, and every
# name it can emit checked against nixos-hardware.
#
# The second half is the one that would otherwise rot silently. The script
# prints strings; the generated flake turns them into
# `inputs.nixos-hardware.nixosModules.<name>`. A name that stops existing --
# upstream renames a module, or a typo lands here -- is not a warning. It is an
# evaluation failure on a user's machine, at the end of an install, after the
# disk is already formatted. So the list of every name the script can produce
# is extracted from the script itself and asserted against the input.
#
# The fixtures are the machines a VM cannot be: an Intel laptop with an iGPU
# and a battery, an AMD desktop with a spinning disk, a hybrid, and a machine
# with an NVMe and no battery. checks.install's guest has one virtio disk, no
# battery and no display controller, so it reaches exactly one of these paths.
let
  # Every module name spelled anywhere in the script. Extracted rather than
  # listed: a second hand-written list would be a list that disagrees, which is
  # the failure mode omarchy-patched-files.sh exists to argue against.
  names = builtins.filter (n: builtins.isString n && n != "") (
    builtins.split "[^a-z0-9-]+" (builtins.readFile ../installer/hardware-modules.sh)
  );
  # A shape, not a prefix. `builtins.substring 0 7 n == "common-"` also caught
  # the bare "common-" that falls out of the phrase "the common-* modules" in
  # the script's own header, and asserted nixos-hardware should have a module
  # by that name.
  candidates = builtins.filter (n: builtins.match "common-[a-z0-9]+(-[a-z0-9]+)*" n != null) names;
  missing = builtins.filter (n: !(inputs.nixos-hardware.nixosModules ? ${n})) candidates;
in
assert
  missing == [ ]
  || throw "hardware-modules.sh names modules nixos-hardware does not have: ${toString missing}";
pkgs.runCommand "nixarchy-hardware-modules"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
    # Printed on success so a reader can see WHICH names were verified, not
    # just that some number of them were.
    verified = toString candidates;
  }
  ''
    mk() { mkdir -p "$1/$2"; echo "$3" > "$1/$2/class"; echo "$4" > "$1/$2/vendor"; }
    battery() { mkdir -p "$1/power_supply/BAT0"; echo Battery > "$1/power_supply/BAT0/type"; }
    # An AC adapter is NOT a battery. A desktop has one, and a laptop test that
    # counted any power_supply would call every machine a laptop.
    ac() { mkdir -p "$1/power_supply/AC"; echo Mains > "$1/power_supply/AC/type"; }
    disk() { mkdir -p "$1/$2/queue"; echo "$3" > "$1/$2/queue/rotational"; }

    cpu() { printf 'processor\t: 0\nvendor_id\t: %s\n' "$2" > "$1"; }

    # An Intel laptop: iGPU, battery, NVMe.
    mk pci/intel "0000:00:02.0" 0x030000 0x8086
    battery cls/intel; disk blk/intel nvme0n1 0
    cpu cpuinfo.intel GenuineIntel

    # An AMD desktop: Radeon, mains only, spinning rust.
    mk pci/amd "0000:03:00.0" 0x030000 0x1002
    ac cls/amd; disk blk/amd sda 1
    cpu cpuinfo.amd AuthenticAMD

    # Hybrid: Intel iGPU + NVIDIA dGPU, battery, SSD.
    mk pci/hybrid "0000:00:02.0" 0x030000 0x8086
    mk pci/hybrid "0000:01:00.0" 0x030000 0x10de
    battery cls/hybrid; disk blk/hybrid nvme0n1 0
    cpu cpuinfo.hybrid GenuineIntel

    # A loop device is not a disk. Without the filter this machine -- no real
    # block device at all -- would read a squashfs loop as non-rotational and
    # claim an SSD, which is what the live ISO looks like from inside.
    mkdir -p blk/loops; disk blk/loops loop0 0
    mk pci/none "0000:00:1f.6" 0x020000 0x8086
    ac cls/none; cpu cpuinfo.none AuthenticAMD

    run() { # run <fixture>
      ( export NIXARCHY_SYSFS_PCI="$PWD/pci/$1" \
               NIXARCHY_SYSFS_CLASS="$PWD/cls/$1" \
               NIXARCHY_SYSFS_BLOCK="$PWD/blk/$1" \
               NIXARCHY_CPUINFO="$PWD/cpuinfo.$1"
        bash ${../installer/hardware-modules.sh} 2>/dev/null ) || true
    }

    fails=0
    want() {
      if printf '%s\n' "$2" | grep -qx "$3"; then echo "  ok      $1"
      else echo "  FAILED  $1: no line /$3/ in:"; printf '%s\n' "$2" | sed 's/^/            /'
        fails=$((fails + 1)); fi
    }
    wantnot() {
      if printf '%s\n' "$2" | grep -qx "$3"; then
        echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
      else echo "  ok      $1"; fi
    }

    i=$(run intel)
    [ -n "$i" ] || { echo "the script printed nothing at all"; exit 1; }
    # cpu-only, NOT common-cpu-intel: that one imports ../../gpu/intel, so an
    # Intel CPU beside a discrete-only GPU would pull the whole Intel media
    # stack for hardware that is not there.
    want    "intel cpu picks cpu-only"  "$i" 'common-cpu-intel-cpu-only'
    wantnot "and not the gpu-importing" "$i" 'common-cpu-intel'
    want    "intel igpu is selected"    "$i" 'common-gpu-intel'
    want    "battery + ssd -> laptop"   "$i" 'common-pc-laptop-ssd'
    # laptop-ssd already imports both; naming them too would import the same
    # module twice under two names.
    wantnot "no duplicate laptop"       "$i" 'common-pc-laptop'
    wantnot "no duplicate ssd"          "$i" 'common-pc-ssd'

    a=$(run amd)
    want    "amd cpu microcode"         "$a" 'common-cpu-amd'
    want    "radeon is selected"        "$a" 'common-gpu-amd'
    # Mains is not a battery, and rotational is not an SSD.
    want    "desktop + hdd -> plain pc" "$a" 'common-pc'
    wantnot "an AC adapter is no laptop" "$a" 'common-pc-laptop'
    wantnot "a spinning disk is no ssd" "$a" 'common-pc-ssd'

    h=$(run hybrid)
    want    "hybrid keeps the igpu"     "$h" 'common-gpu-intel'
    # The deliberate omission. common-gpu-nvidia is not a driver choice: the
    # choice is open vs legacy_580 split at PCI id 0x1e00, plus PRIME bus ids
    # in decimal on a hybrid. Wrong there is a machine with no screen, so the
    # doctor prints it for a person to confirm instead.
    wantnot "nvidia is never automatic" "$h" 'common-gpu-nvidia'

    n=$(run none)
    want    "no gpu still picks a cpu"  "$n" 'common-cpu-amd'
    wantnot "ethernet is not a gpu"     "$n" 'common-gpu-intel'
    # The live ISO's own shape.
    wantnot "a loop is not an ssd"      "$n" 'common-pc-ssd'
    want    "and falls back to pc"      "$n" 'common-pc'

    [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
    echo "selection is right, and nixos-hardware has: $verified"
    touch $out
  ''
