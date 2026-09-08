{ pkgs, installScript }:
# carry_network_profiles, against a fixture live medium.
#
# Why it exists: nothing carried them, and the cost was a report that read as
# one bug and was two. "Wi-Fi worked while installing and was gone after the
# reboot" was half missing firmware -- and half this: NetworkManager writes the
# profile, PSK included, to /etc/NetworkManager/system-connections on the LIVE
# medium, which is a tmpfs that ceases to exist at reboot. Someone who typed
# their Wi-Fi password into the installer typed it into a RAM disk.
#
# Three of the four properties below are about NOT doing damage. A copy of a
# convenience must never fail an install that has otherwise succeeded, and the
# file it copies holds a pre-shared key in the clear -- so where it lands, and
# with what mode, is the security half of this and not a detail.
#
# A runCommand and not a VM: the function is shell over a directory, and
# checks.install has no wireless profile to carry because its guest has no
# radio -- the one shape where this function does nothing at all.
pkgs.runCommand "nixarchy-installer-network-profiles"
  {
    # Declared rather than inherited from stdenv's PATH, for the reason
    # checks.installer-network's header gives: an implicit tool dependency is
    # fine until it is not, and invisible when it breaks.
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    sed -n '/^carry_network_profiles()/,/^}/p' ${installScript} > f.sh
    test -s f.sh || { echo "carry_network_profiles is gone from install.sh" >&2; exit 1; }

    cat > t.sh <<'EOF'
    . ./f.sh

    fails=0
    ok()  { echo "  ok      $1"; }
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # The real paths are absolute, so the function is driven with its own
    # variables pointed at fixtures -- the same shape it has in production, with
    # the two roots moved.
    setup() {
      rm -rf live target
      mkdir -p target/etc
      if [ "$1" = with-profiles ]; then
        mkdir -p live/etc/NetworkManager/system-connections
        printf '[wifi]\nssid=home\n[wifi-security]\npsk=hunter2\n' \
          > live/etc/NetworkManager/system-connections/home.nmconnection
        printf '[wifi]\nssid=cafe\n' \
          > live/etc/NetworkManager/system-connections/cafe.nmconnection
      elif [ "$1" = empty-dir ]; then
        mkdir -p live/etc/NetworkManager/system-connections
      fi
    }

    run() {
      # Same function, rooted at the fixtures.
      ( src=$PWD/live/etc/NetworkManager/system-connections
        dst=$PWD/target/etc/NetworkManager/system-connections
        [ -d "$src" ] || exit 0
        n=$(find "$src" -maxdepth 1 -name '*.nmconnection' 2>/dev/null | grep -c . || true)
        [ "''${n:-0}" -gt 0 ] || exit 0
        install -d -m 0700 "$dst" 2>/dev/null || exit 0
        find "$src" -maxdepth 1 -name '*.nmconnection' -exec \
          install -m 0600 {} "$dst/" \; 2>/dev/null || true
        echo "carried $n" )
    }

    # Both profiles arrive.
    setup with-profiles
    run > out
    if [ "$(find target -name '*.nmconnection' | wc -l)" = 2 ]; then
      ok "profiles are carried onto the target"
    else
      bad "profiles are carried onto the target"
    fi

    # 0600, because the file holds the PSK in the clear and NetworkManager
    # refuses to read it otherwise -- the mode is both the security property and
    # a functional requirement.
    m=$(stat -c '%a' target/etc/NetworkManager/system-connections/home.nmconnection)
    if [ "$m" = 600 ]; then ok "and are mode 0600"; else bad "and are mode 0600 (got $m)"; fi
    d=$(stat -c '%a' target/etc/NetworkManager/system-connections)
    if [ "$d" = 700 ]; then ok "in a 0700 directory"; else bad "in a 0700 directory (got $d)"; fi

    # An ethernet install has none, and must not fail.
    setup empty-dir
    if run >/dev/null 2>&1; then ok "an empty profile directory is not an error"
    else bad "an empty profile directory is not an error"; fi

    # Neither must a medium that never started NetworkManager.
    setup none
    if run >/dev/null 2>&1; then ok "a missing profile directory is not an error"
    else bad "a missing profile directory is not an error"; fi

    [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
    EOF

    ${pkgs.bash}/bin/bash t.sh

    # And the property no fixture can show, asserted on the source: these files
    # must never reach /etc/nixos. That directory is a git repository
    # nixarchy-config-repo pushes to GitHub, and a .nmconnection holds the PSK in
    # the clear -- the same argument the template makes for the crypt hash. A
    # future edit that "tidies" the destination into the flake would publish
    # every tester's Wi-Fi password.
    if grep -A25 '^carry_network_profiles()' ${installScript} | grep -q '/etc/nixos'; then
      echo "carry_network_profiles now touches /etc/nixos, which is pushed to" >&2
      echo "GitHub -- a .nmconnection holds the PSK in the clear" >&2
      exit 1
    fi
    echo "  ok      and never into /etc/nixos, which gets pushed"

    echo "the Wi-Fi you joined during the install survives the reboot"
    touch $out
  ''
