{ inputs, pkgs, ... }:
# The installed system must carry firmware without depending on a virt probe.
#
# What this defends:
#
#   Wireless, Bluetooth and most graphics need a firmware blob.
#   hardware.enableRedistributableFirmware is what puts one on the machine,
#   and nominally it comes from hardware-configuration.nix -- but only there:
#   nixos-generate-config imports installer/scan/not-detected.nix, whose whole
#   content is that option, and it imports it inside
#
#     if ($virt eq "none") {          nixos-generate-config.pl:321
#
#   so an installed machine's firmware hangs on a generated import, which
#   hangs on systemd-detect-virt.
#
#   That branch cannot be tested by any VM in this repo. Every guest reports a
#   virt type, so every install check takes the path where the option is FALSE
#   and the path real users are on is the one nothing covers. The ISO enables
#   it (installation-device.nix), which makes the failure worse rather than
#   better: wifi works while installing and is gone afterwards, and the report
#   that arrives says "it worked during the install".
#
#   A user on an Intel AX201 hit exactly this shape -- iwlwifi bound, no
#   wlan0 in nmtui -- and asked whether we should ship iwctl.
#
# Two things are asserted. The first is that the module sets it at all. The
# second is the one that rots quietly: that it is a DEFAULT, not forced, so an
# adopter who has a reason to ship no blobs can still say so. A guard that
# only checked the value would pass on an mkForce that takes their choice away.
pkgs.runCommand "nixarchy-firmware-guard" { } (
  let
    inherit (inputs.self.nixosConfigurations) reference iso;

    # A configuration with the option explicitly off. If the module used
    # mkForce, or plain assignment at the same priority, this would either
    # evaluate to true anyway or fail to evaluate at all -- and the whole
    # point of mkDefault is that it does neither.
    overridden = reference.extendModules {
      modules = [ { hardware.enableRedistributableFirmware = false; } ];
    };

    b = v: if v then "true" else "false";
  in
  ''
    fail=0
    check() { # check <name> <actual> <wanted>
      if [ "$2" = "$3" ]; then echo "  ok      $1"
      else echo "  FAILED  $1: got $2, wanted $3"; fail=1; fi
    }

    # The installed system. This is the assertion that was false before the
    # module set it, on every machine whose hardware-configuration.nix did not
    # happen to be generated on bare metal.
    check "installed systems get firmware" \
      ${b reference.config.hardware.enableRedistributableFirmware} true

    # The ISO already had it, from installation-device.nix. Asserted so that
    # the day someone trims the image, the installer does not quietly lose the
    # wifi it needs to reach a binary cache.
    check "the ISO keeps firmware" \
      ${b iso.config.hardware.enableRedistributableFirmware} true

    # Still overridable.
    check "an adopter can turn it off" \
      ${b overridden.config.hardware.enableRedistributableFirmware} false

    # NOT enableAllFirmware: that one needs allowUnfree, and turning it on for
    # everyone would make every adopter's build fail on an unfree licence to
    # fix a Broadcom card most of them do not have. The doctor's Wireless
    # section names it per-card instead.
    check "all-firmware stays opt-in" \
      ${b reference.config.hardware.enableAllFirmware} false

    [ "$fail" = 0 ] || exit 1
    echo "the installed system carries firmware, and can still refuse it"
    touch $out
  ''
)
