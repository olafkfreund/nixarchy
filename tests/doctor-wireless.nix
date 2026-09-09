{ pkgs, doctor }:
# The doctor's Wireless section, driven against fixture machines.
#
# Written because two users in one week reported the same thing -- no wlan0 in
# nmtui, rfkill unblocked, NetworkManager restarted -- and one of them asked
# whether nixarchy should ship iwctl. It should not: with no netdev, iwctl
# shows the same nothing nmtui does, because both ask the kernel and the kernel
# has no interface to give. The section exists to say WHICH of the three cases
# it is, and this test exists because none of the three can occur in a VM.
#
# checks.install's guest has a virtio NIC and no wireless anything, so every
# branch here would otherwise be untested -- the shape that let the doctor's
# no-VAAPI-driver branch ship unreachable (#352).
#
# Fixtures are real device ids: 0x8086/0x2725 is Intel AX200, 0x14e4/0x43a0 a
# Broadcom BCM4360, 0x10ec/0xc821 a Realtek 8821CE -- the three cards behind
# the overwhelming majority of "no wlan0 on NixOS" reports.
pkgs.runCommand "nixarchy-doctor-wireless" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  # <root> <addr> <vendor> <device> [driver]
  wifi() {
    mkdir -p "$1/$2"
    echo 0x028000 > "$1/$2/class"
    echo "$3" > "$1/$2/vendor"
    echo "$4" > "$1/$2/device"
    if [ -n "$5" ]; then mkdir -p "$1/drv/$5"; ln -s "../drv/$5" "$1/$2/driver"; fi
  }
  # A netdev with a phy80211, which is what cfg80211 creates for every driver
  # that successfully registers a wiphy. That link -- not the interface name --
  # is what separates "the driver worked" from "the driver loaded".
  netdev() { mkdir -p "$1/$2/phy80211"; }

  # No wireless card at all: an ethernet controller, to prove the class filter
  # does not count 0x0200 as wifi. Without this the "no card" branch passes on
  # an empty directory, which proves only that the loop can find nothing.
  mkdir -p fix/none/0000:00:1f.6
  echo 0x020000 > fix/none/0000:00:1f.6/class
  echo 0x8086 > fix/none/0000:00:1f.6/vendor

  wifi fix/intel-nofw  "0000:00:14.3" 0x8086 0x2725 iwlwifi
  wifi fix/broadcom    "0000:03:00.0" 0x14e4 0x43a0 ""
  wifi fix/realtek     "0000:02:00.0" 0x10ec 0xc821 ""
  wifi fix/working     "0000:00:14.3" 0x8086 0x2725 iwlwifi

  # Only the working fixture gets an interface. The other three are the whole
  # point: a card the user can see in lspci and cannot see in nmtui.
  mkdir -p net/empty
  netdev net/up wlan0
  # `lo` in both, because a real machine always has one and a check that only
  # passes on a machine with no interfaces at all is not checking much.
  mkdir -p net/empty/lo net/up/lo

  export HOME=$PWD/home USER=tester
  mkdir -p "$HOME"

  run() { # run <pci fixture> <net fixture>
    ( export NIXARCHY_SYSFS_PCI="$PWD/fix/$1" NIXARCHY_SYSFS_NET="$PWD/net/$2"
      ${doctor}/bin/nixarchy-doctor 2>&1 ) || true
  }

  fails=0
  want() {
    if printf '%s' "$2" | grep -q "$3"; then echo "  ok      $1"
    else
      echo "  FAILED  $1: no /$3/ in the output"
      # And WHAT it printed instead.
      #
      # Without this the failure names the string it wanted and nothing else,
      # so a case that fails in CI and passes locally -- which this file did
      # on 2026-09-09, same derivation hash, opposite results -- leaves
      # nothing to reason from. The Wireless section is a dozen lines; print
      # it, indented, and the next occurrence is an answer rather than a
      # rerun.
      printf '%s\n' "$2" | sed -n '/Wireless/,/^$/p' | sed 's/^/          | /'
      fails=$((fails + 1))
    fi
  }
  wantnot() {
    if printf '%s' "$2" | grep -q "$3"; then
      echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
    else echo "  ok      $1"; fi
  }

  up=$(run working up)
  # Same guard as the graphics test: every assertion below fails identically
  # when the doctor printed nothing, which reads like every rule being wrong.
  printf '%s' "$up" | grep -q 'Wireless' || {
    echo "the doctor printed no Wireless section at all:"; printf '%s\n' "$up"; exit 1; }
  want    "a working card is named"    "$up" 'Wireless interface wlan0 is up'
  want    "and its driver with it"     "$up" 'Intel, driver iwlwifi'
  wantnot "no advice when it works"    "$up" 'enableAllFirmware'

  n=$(run none empty)
  want    "no card is said plainly"    "$n" 'No PCI wireless card here'
  # Ethernet is not wireless. A class filter of 0x02* rather than 0x0280*
  # would call this Intel NIC a wifi card with no driver and send the user
  # after firmware for a cable.
  wantnot "ethernet is not counted"    "$n" 'wireless card with no driver'
  # The honest limit, stated in the output rather than only in a comment: this
  # walks PCI, so a USB adapter is invisible and must not be denied.
  want    "USB is not ruled out"       "$n" 'USB adapter'

  b=$(run broadcom empty)
  want    "broadcom named as unbound"  "$b" 'Broadcom wireless card with no driver'
  want    "its device id is printed"   "$b" '0x43a0'
  want    "the fix is pasteable"       "$b" 'hardware.enableAllFirmware = true'
  want    "allowUnfree is mentioned"   "$b" 'allowUnfree'
  # broadcom_sta and b43 cannot both load. Advice that omits the conflict is
  # advice that produces a machine which builds and still has no wifi.
  want    "the conflict is named"      "$b" 'pick one'

  r=$(run realtek empty)
  want    "realtek named as unbound"   "$r" 'Realtek wireless card with no driver'
  want    "out-of-tree module named"   "$r" 'rtl8821ce'
  # Realtek is not Broadcom. enableAllFirmware does nothing for an 8821CE, and
  # offering it here would be a paste-in line that changes nothing and reads
  # like the fix -- the same mistake as intel-media-driver on an NVIDIA box.
  wantnot "no broadcom fix on realtek" "$r" 'enableAllFirmware = true'

  i=$(run intel-nofw empty)
  want    "bound-but-dead is distinct" "$i" 'driver iwlwifi loaded, but no interface'
  want    "the log is where to look"   "$i" 'journalctl -b -k'
  # This is NOT the no-driver case, and saying so is the entire value of
  # splitting them: "install a driver" is wrong advice for a card whose driver
  # is already loaded and merely could not find its firmware.
  wantnot "not called driverless"      "$i" 'card with no driver'

  # The question that prompted all of this: "maybe ship iwctl?". The doctor
  # must never send someone after a second wireless UI for a missing netdev.
  #
  # Matched on a RECOMMENDATION, not on the string -- the same distinction the
  # graphics test draws between intel-media-driver in prose and in the snippet.
  # A first draft of this forbade the bare word and failed on the two branches
  # that name iwctl in exactly the sentence that answers the question ("nmtui,
  # iwctl, wpa_cli -- will show the same nothing"). Deleting that sentence to
  # make an assertion pass would have removed the one line worth reading.
  # `c`, not `out`: $out is the builder's own output path. Shadowing it let
  # every assertion pass and then sent `touch $out` at /etc/nixos.
  for c in "$b" "$r" "$i"; do
    wantnot "iwctl is not prescribed" "$c" 'iwd\|install.*iwctl\|try iwctl'
  done
  # And the sentence itself is load-bearing, so it is asserted rather than
  # merely tolerated: without it "no driver" reads as a NetworkManager fault
  # and the next thing tried is another client.
  want "why no UI will help" "$b" 'nmtui, iwctl, wpa_cli'

  [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
  echo "the doctor tells the three no-wlan0 cases apart"
  touch $out
''
