{ inputs, pkgs, ... }:
# The ISO can actually associate to a Wi-Fi network.
#
# What this defends, and it cost a tester two evenings:
#
#   installer/cd.nix used to force networking.wireless.enable = false, on the
#   reasoning that installation-cd-minimal's wpa_supplicant conflicts with
#   NetworkManager and one of them has to go.
#
#   NetworkManager does not avoid wpa_supplicant. It DRIVES it, and its own
#   module says so (networkmanager.nix:694-698):
#
#     # Enable wpa_supplicant but fully control it over DBus
#     wireless.enable = true;
#     wireless.autoDetectInterfaces = false;
#     wireless.dbusControlled = true;
#
#   The mkForce overrode that, so NM was left with a backend it was configured
#   to use and no way to start it. On a ThinkPad T15 with a bound iwlwifi and
#   an unblocked radio:
#
#     device (wlp0s20f3): Couldn't initialize supplicant interface:
#       Failed to D-Bus activate wpa_supplicant service
#
#   every thirteen seconds, forever. The net image cannot install without a
#   network, so for anyone without a cable that image simply did not work.
#
# Evaluation, not a VM, and that is the point: no VM in this repo has a radio,
# so checks.install-iso boots with -nic none and every install test uses a
# virtio NIC. There is nowhere in the suite this could have been caught by
# running something -- only by asking the configuration what it says.
let
  c = inputs.self.nixosConfigurations.iso.config;
  b = v: if v then "true" else "false";
in
pkgs.runCommand "nixarchy-iso-wifi" { } ''
  fail=0
  check() { # check <name> <actual> <wanted>
    if [ "$2" = "$3" ]; then echo "  ok      $1"
    else echo "  FAILED  $1: got $2, wanted $3"; fail=1; fi
  }

  # The one that was false. NM needs a supplicant it can activate over D-Bus,
  # and the whole failure was that there was not one.
  check "the ISO has a wpa_supplicant to drive" \
    ${b c.networking.wireless.enable} true

  # And that it is NM driving it rather than a standalone supplicant, which is
  # the conflict the old comment was right to worry about -- these two are how
  # NetworkManager prevents it, and they are the reason forcing enable=false
  # was never necessary.
  check "and drives it over D-Bus" \
    ${b c.networking.wireless.dbusControlled} true
  check "without grabbing interfaces itself" \
    ${b c.networking.wireless.autoDetectInterfaces} false

  # NM itself, since everything above is meaningless without it.
  check "NetworkManager is on" \
    ${b c.networking.networkmanager.enable} true

  # The backend NM was configured for. iwd would be a legitimate other answer
  # and would need wireless.enable false -- so this asserts the PAIR is
  # consistent rather than either half alone.
  check "the configured backend is wpa_supplicant" \
    "${c.networking.networkmanager.wifi.backend}" wpa_supplicant

  # And the firmware, because a supplicant with no blob is the same dead end
  # one layer down: the ISO's own iwlwifi/rtl_nic blobs come from here.
  check "the ISO carries redistributable firmware" \
    ${b c.hardware.enableRedistributableFirmware} true

  [ "$fail" = 0 ] || exit 1
  echo "the ISO can associate to a network"
  touch $out
''
