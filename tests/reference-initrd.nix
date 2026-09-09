{ inputs, pkgs }:
# The reference machine's initrd can mount a disk it was not built on.
#
# This is a precondition for offline install stage 3 (#436), and it is the kind
# that is invisible until it is fatal. Stage 3 installs the REFERENCE closure
# rather than one built from the machine's own detected hardware-configuration
# .nix -- that is the whole point, since a per-machine closure is a per-machine
# BUILD and offline there is nothing to build with. So the installed machine
# boots the reference's initrd, and whatever is not in it cannot be mounted.
#
# Measured before `hardware.enableAllHardware` was set: the ISO carried 103
# initrd modules and the reference carried 63. The 61 missing included md_mod
# and raid0/1/10/456, hpsa, 3w-9xxx, arcmsr, aic79xx, hv_storvsc, vmxnet3 and
# thirty-odd pata_/sata_ controllers. A machine on any of those would have come
# up in an initrd with no driver for its root device.
#
# That the ISO has them is no help at all, and the distinction is the reason
# this check exists: an installed machine boots ITS OWN initrd, not the
# installer's. The two are different closures and only one of them is on the
# disk afterwards.
#
# The ISO is the yardstick because it is the one configuration in this repo
# that already aims at "any hardware someone might have" -- nixpkgs maintains
# that list in installation-cd-minimal.nix, so comparing against it means the
# floor rises when nixpkgs raises it, rather than when somebody remembers to
# edit a list here.
let
  inherit (pkgs) lib;

  iso = inputs.self.nixosConfigurations.iso.config.boot.initrd.availableKernelModules;
  reference = inputs.self.nixosConfigurations.reference.config.boot.initrd.availableKernelModules;

  # Modules the ISO carries that an installed machine provably does not need.
  # Each is excluded for a stated reason, and the reasons are checkable rather
  # than assertions of taste -- an exclusion list without them is where a real
  # gap hides as a deliberate one.
  excluded = {
    # The live medium itself. An installed machine boots from a disk.
    iso9660 = "the ISO's own filesystem";
    squashfs = "the ISO's compressed store";
    overlay = "the ISO's writable overlay";

    # Software RAID. installer/disk-config.nix contains no RAID of any kind --
    # it lays down a single-disk btrfs layout and nothing else -- so this
    # installer cannot produce a machine whose root is on mdraid, and an initrd
    # driver for one would be covering a case that cannot arise.
    #
    # These do NOT come from hardware.enableAllHardware in any case; they come
    # from boot.swraid.enable, which is a different decision with mdadm
    # attached. If this installer ever grows a RAID layout, that option is what
    # to turn on, and this list is where the reason it was excluded is written.
    md_mod = "boot.swraid.enable, and disk-config.nix creates no RAID";
    raid0 = "boot.swraid.enable, and disk-config.nix creates no RAID";
    raid1 = "boot.swraid.enable, and disk-config.nix creates no RAID";
    raid10 = "boot.swraid.enable, and disk-config.nix creates no RAID";
    raid456 = "boot.swraid.enable, and disk-config.nix creates no RAID";
  };

  missing = builtins.filter (m: !(builtins.elem m reference)) iso;
  unexplained = builtins.filter (m: !(excluded ? ${m})) missing;

  # An exclusion for a module the ISO no longer carries is a stale entry, and
  # stale entries are how a list stops describing anything. Loud in both
  # directions, as every other manifest in this repo is.
  stale = builtins.filter (m: !(builtins.elem m iso)) (builtins.attrNames excluded);
in
pkgs.runCommand "nixarchy-reference-initrd"
  {
    isoCount = toString (builtins.length iso);
    refCount = toString (builtins.length reference);
    unexplained = builtins.concatStringsSep " " unexplained;
    stale = builtins.concatStringsSep " " stale;

    # The initrd itself, BUILT.
    #
    # Comparing names is not enough and this check learned that the hard way:
    # it passed while the machine could not build, because all-hardware gates
    # part of its list on the kernel version -- `pata_qdi` only below 7.0 --
    # and a list computed for the wrong kernel names a module that does not
    # exist. modprobe said so three derivations away, in modules-shrunk:
    #
    #   root module: pata_qdi
    #   modprobe: FATAL: Module pata_qdi not found in directory
    #             .../linux-7.2.4-modules/lib/modules/7.2.4
    #
    # So this depends on the real initrd. A name that no kernel module backs
    # now fails HERE, naming the initrd, instead of in whichever job happened
    # to build a toplevel first.
    initrd = inputs.self.nixosConfigurations.reference.config.system.build.initialRamdisk;
    reasons = lib.concatStringsSep "\n" (lib.mapAttrsToList (m: why: "  ${m}: ${why}") excluded);
  }
  ''
    echo "initrd modules: ISO $isoCount, reference $refCount"

    # A floor. Both lists coming back empty would satisfy every test below
    # while proving nothing at all -- the failure mode this repo has been bitten
    # by more than once.
    if [ "$isoCount" -lt 50 ] || [ "$refCount" -lt 50 ]; then
      echo "one of the module lists is implausibly short; the check cannot" >&2
      echo "answer anything and is refusing rather than passing." >&2
      exit 1
    fi

    if [ -n "$unexplained" ]; then
      echo "::error::the reference initrd lacks modules the ISO carries:" >&2
      for m in $unexplained; do echo "  $m" >&2; done
      echo >&2
      echo "  Offline install (#436) copies the reference closure, so an" >&2
      echo "  installed machine boots THIS initrd. A missing storage driver" >&2
      echo "  is a machine that cannot find its root filesystem." >&2
      echo "  Fix: hardware.enableAllHardware in modules/nixos.nix, or add" >&2
      echo "  the module to the exclusion list in this file WITH a reason." >&2
      exit 1
    fi

    if [ -n "$stale" ]; then
      echo "::error::these exclusions name modules the ISO no longer has:" >&2
      for m in $stale; do echo "  $m" >&2; done
      echo "  Remove them: an exclusion that excludes nothing hides the next" >&2
      echo "  real gap behind a list that looks considered." >&2
      exit 1
    fi

    # Named so a reader sees WHY the check depends on a 60 MB build.
    echo "the reference initrd builds: $initrd"

    echo "every ISO module is in the reference, or excluded with a reason:"
    printf '%s\n' "$reasons"
    touch $out
  ''
