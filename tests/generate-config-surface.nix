{ inputs, pkgs, ... }:
# Every attribute `nixos-generate-config` can emit, against what the ISO bakes.
#
# The failure this exists for, in full, because it cost two users an install
# and most of a day to find:
#
#   nixpkgs c043004 added Intel NPU detection. nixos-generate-config.pl matches
#   PCI 8086:7d1d and friends and writes `hardware.cpu.intel.npu.enable = true`
#   into hardware-configuration.nix. hardware/cpu/intel-npu.nix turns that into
#   pkgs.intel-npu-driver.validation in environment.systemPackages. That
#   package is not in either reference closure, so the ISO does not carry it;
#   it is a cmake build, so building it pulls cmake, libarchive and acl, none
#   of which are baked either; and the offline image could not substitute. The
#   install walked back to the source bootstrap and died fetching
#   acl-2.4.0.tar.gz -- after partitioning the disk.
#
# qemu exposes no NPU, so no VM has ever emitted that attribute, and every
# install check passed throughout.
#
# The general shape: installer/cd.nix bakes the closures of two reference
# systems plus inputDerivation for their toplevel, initrd and etc, on the
# argument that a real machine differs from them only by "a few dozen text
# derivations". That argument holds right up until generate-config adds a
# PACKAGE. Then the difference is a compiler.
#
# So this asserts the argument rather than trusting it: for every attribute
# that tool can emit, either the package set is unchanged, or the packages it
# adds are ones the image carries.
#
# The list is not invented. It is `push @attrs` in nixos-generate-config.pl of
# the pinned nixpkgs, read out in full. When nixpkgs adds the next one, this
# check goes red on the pin bump that introduces it -- which is the whole
# point, and roughly a year earlier than a user finding it.
let
  inherit (pkgs) lib;

  reference = inputs.self.nixosConfigurations.reference;

  # What the ISO actually carries, which is the question -- not what the
  # encrypted reference alone carries. installer/cd.nix bakes these three and
  # this list is kept in step with it by hand; if they drift, this check gets
  # stricter than the image, which fails loudly rather than quietly.
  baked = [
    reference
    inputs.self.nixosConfigurations.reference-unencrypted
    inputs.self.nixosConfigurations.reference-hardware
  ];

  # Comparing the PATHS rather than the closure keeps this an evaluation
  # rather than a build.
  #
  # unsafeDiscardStringContext, or this check BUILDS what it is complaining
  # about: a store path interpolated into `report` is a build input of the
  # runCommand, so the first run compiled prl-tools, VirtualBox additions and
  # a Parallels .dmg in order to print their names. The text is all this needs.
  pathsOf =
    c: map (p: builtins.unsafeDiscardStringContext "${p}") (c.config.system.path.paths or [ ]);

  onImage = lib.unique (lib.concatMap pathsOf baked);

  # Every attribute the tool can write, with a value that turns it on. Two are
  # deliberately absent: nixpkgs.hostPlatform and
  # nixpkgs.config.allowUnfreePackages are already set by the flake, and
  # setting them again asserts nothing about packages.
  candidates = [
    {
      name = "hardware.cpu.intel.npu.enable";
      module = {
        hardware.cpu.intel.npu.enable = true;
      };
    }
    {
      name = "hardware.cpu.amd.updateMicrocode";
      module = {
        hardware.cpu.amd.updateMicrocode = true;
      };
    }
    {
      name = "hardware.cpu.intel.updateMicrocode";
      module = {
        hardware.cpu.intel.updateMicrocode = true;
      };
    }
    {
      name = "boot.swraid.enable";
      module = {
        boot.swraid.enable = true;
      };
    }
    {
      name = "networking.enableIntel2200BGFirmware";
      module = {
        networking.enableIntel2200BGFirmware = true;
      };
    }
    {
      name = "networking.enableIntel3945ABGFirmware";
      module = {
        networking.enableIntel3945ABGFirmware = true;
      };
    }
    {
      name = "services.xserver.videoDrivers";
      module = {
        services.xserver.videoDrivers = [ "modesetting" ];
      };
    }
    {
      name = "virtualisation.hypervGuest.enable";
      module = {
        virtualisation.hypervGuest.enable = true;
      };
    }
    {
      name = "virtualisation.virtualbox.guest.enable";
      module = {
        virtualisation.virtualbox.guest.enable = true;
      };
    }
    {
      name = "hardware.parallels.enable";
      module = {
        hardware.parallels.enable = true;
        nixpkgs.config.allowUnfree = true;
      };
      # prl-tools is built from a Parallels Desktop .dmg fetched from
      # Parallels, unfree and not redistributable. It cannot go on an image
      # this project publishes, so there is nothing to bake. What covers it
      # instead is #384: both images now carry substituters, and a machine
      # running under Parallels is a desktop VM with a working network by
      # definition -- the case this check exists for is the laptop with an
      # NPU and a hotel wifi, not a guest that cannot reach the internet.
      excused = "unfree and undistributable; a Parallels guest has a network";
    }
    {
      name = "boot.isNspawnContainer";
      module = {
        boot.isNspawnContainer = true;
      };
      # nixos-generate-config.pl:317 emits this only when $virt is
      # "systemd-nspawn" -- when the tool is running INSIDE a container. This
      # installer boots a kernel and partitions a physical disk, so it is
      # never in that state and the attribute is never written. Excused
      # because it is unreachable, not because it is inconvenient.
      excused = "only emitted inside an nspawn container; the installer never is";
    }
  ];

  added =
    c:
    let
      v = reference.extendModules { modules = [ c.module ]; };
      # Against the union of what is BAKED, not against the reference alone:
      # an attribute that adds intel-npu-driver is fine once the image
      # carries intel-npu-driver, and that is the whole fix.
      new = lib.subtractLists onImage (pathsOf v);
    in
    {
      inherit (c) name;
      excused = c.excused or null;
      packages = map baseNameOf new;
    };

  results = map added candidates;
  offenders = lib.filter (r: r.packages != [ ] && r.excused == null) results;

  report = lib.concatMapStrings (
    r: "  ${r.name}\n${lib.concatMapStrings (p: "      + ${p}\n") r.packages}"
  ) offenders;

  clean = lib.concatMapStrings (r: "  ${r.name}\n") (
    lib.filter (r: r.packages == [ ] && r.excused == null) results
  );

  # Printed on success too. An exclusion nobody can see is an allowlist.
  excusedReport = lib.concatMapStrings (r: "  ${r.name}\n      ${r.excused}\n") (
    lib.filter (r: r.excused != null) results
  );
in
pkgs.runCommand "nixarchy-generate-config-surface"
  {
    inherit report clean excusedReport;
    offenderCount = builtins.length offenders;
  }
  ''
    echo "attributes the image already satisfies:"
    printf '%s' "$clean"
    echo
    echo "attributes excused, with the reason:"
    printf '%s' "$excusedReport"
    echo

    if [ "$offenderCount" -eq 0 ]; then
      echo "every generate-config attribute is one this image can satisfy"
      touch $out
      exit 0
    fi

    echo "these attributes need packages NO baked reference carries:" >&2
    printf '%s' "$report" >&2
    cat >&2 <<'WHY'

    nixos-generate-config writes these into hardware-configuration.nix when it
    finds the hardware. The offline image bakes two reference closures; a
    package that is not in either is one the machine must BUILD, and building
    it needs a compiler the image does not carry, which is the source
    bootstrap.

    Two ways to make this green, and both are real fixes:

      - bake the packages, by turning the attribute on in
        nixosConfigurations.reference-hardware (flake.nix), which
        installer/cd.nix bakes for exactly this reason; or
      - have installer/install.sh comment the attribute out of the generated
        hardware-configuration.nix, the way reuse_baked_initrd already rewrites
        the initrd lines, so it applies at the first update instead.

    Adding the attribute to this check's allowlist is not one of them.
    WHY
    exit 1
  ''
