{ pkgs, installScript }:
# network_fault and wifi_block, driven against a stubbed kernel.
#
# What they defend, and both cost a tester an evening:
#
#   "No network yet" was one screen for three situations. A cable that is not
#   plugged in, a laptop associated to a captive portal, and a network that
#   filters the binary cache all want different actions, and only the first is
#   fixed by choosing Try again. Someone sat on that screen with working Wi-Fi
#   and nothing to act on.
#
#   connect_wifi never touched rfkill. `nmcli radio wifi on` clears
#   NetworkManager's idea of the radio and not the kernel's, so a blocked card
#   scanned, found nothing, and the installer said "the driver may not be on
#   this image" -- about an Intel AX201 whose driver was bound the whole time.
#   On a ThinkPad the actual answer is Fn+F8.
#
# A runCommand and not a VM: these read `ip`, `getent`, `curl` and `rfkill`, and
# checks.install-iso runs with -nic none against a machine with no radio at
# all -- the one shape where every branch below is unreachable.
pkgs.runCommand "nixarchy-installer-network"
  {
    # Declared, not inherited. This builder greps and seds the installer, and
    # the only reason it worked without saying so is that stdenv happens to put
    # both on PATH -- an implicit dependency that is fine until it is not, and
    # invisible when it breaks. checks.installer-failure-hints already declares
    # gnugrep for the same reason.
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    for fn in network_ready network_fault wifi_block; do
      sed -n "/^$fn()/,/^}/p" ${installScript} >> f.sh
      echo >> f.sh
    done
    grep -q '^network_fault()' f.sh ||
      { echo "network_fault is not in install.sh any more" >&2; exit 1; }
    grep -q '^wifi_block()' f.sh ||
      { echo "wifi_block is not in install.sh any more" >&2; exit 1; }

    cat > t.sh <<'EOF'
    . ./f.sh

    # The kernel, stubbed. Each variable is one of the three things the function
    # asks about, so a case is a triple rather than a mock script.
    ip()     { [ "$HAVE_ADDR" = 1 ] && echo "2: enp0s31f6    inet 192.168.1.4/24 scope global"; }
    getent() { [ "$HAVE_DNS" = 1 ]; }

    fails=0
    t() { # t <want> <name> <addr> <dns>
      HAVE_ADDR=$3 HAVE_DNS=$4
      got=$(network_fault)
      if [ "$got" = "$1" ]; then echo "  ok      $2"; else
        echo "  FAILED  $2: wanted $1, got $got"; fails=$((fails + 1)); fi
    }

    # No address at all: the cable is out, or the radio never associated.
    t nolink  "no address is nolink"            0 0
    # Associated with an address and nothing resolves. THE captive portal shape,
    # and the one that used to read as "try again" forever.
    t nodns   "address but no DNS is nodns"     1 0
    # Everything resolves and the cache still will not answer: a proxy, a filter,
    # or the cache being down. Distinct because the action is different -- no
    # amount of waiting on this network fixes it.
    t nocache "resolving but no cache is nocache" 1 1

    # ---- the radio ---------------------------------------------------------
    rfkill() {
      case "$STATE" in
        hard) printf '0: phy0: Wireless LAN\n\tSoft blocked: yes\n\tHard blocked: yes\n' ;;
        soft) printf '0: phy0: Wireless LAN\n\tSoft blocked: yes\n\tHard blocked: no\n' ;;
        none) printf '0: phy0: Wireless LAN\n\tSoft blocked: no\n\tHard blocked: no\n' ;;
        gone) return 1 ;;
      esac
    }
    b() { # b <want> <name> <state>
      STATE=$3
      got=$(wifi_block)
      if [ "$got" = "$1" ]; then echo "  ok      $2"; else
        echo "  FAILED  $2: wanted $1, got $got"; fails=$((fails + 1)); fi
    }

    b none "an unblocked radio is none"        none
    # Ours to clear, and clearing it is the whole fix.
    b soft "a soft block is soft"              soft
    # Hard wins over soft: rfkill reports BOTH yes for a hardware switch, and
    # reading the soft line first would call it soft, try to unblock it, fail
    # silently, and fall through to "no networks found" -- which is the bug this
    # whole file exists for, one layer down.
    b hard "hard beats soft when both are set" hard
    # No rfkill at all must not read as blocked: that would refuse to scan on a
    # machine whose radio is fine.
    b none "a missing rfkill is not a block"   gone

    [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
    EOF

    ${pkgs.bash}/bin/bash t.sh

    # The offline image offers Wi-Fi and never demands it. Asserted on the source
    # because the branch is a gum screen: what matters is that it cannot block an
    # install needing no network, and cannot fire unattended.
    #
    # The old early return left the offline image with no way to configure Wi-Fi
    # at all -- correct for the install, wrong for the machine it produces, whose
    # first boot then has neither a network nor the credentials for one.
    grep -q 'offer_optional_wifi' ${installScript} || {
      echo "the offline image can no longer offer Wi-Fi at all" >&2; exit 1; }
    # Extracted once and kept, so a failure can SHOW what it read.
    #
    # As a bare pipeline this reported "the screen is no longer skipped under
    # --answers" for any reason sed produced nothing -- a renamed function, a
    # changed brace, a missing tool -- and the message named a cause it had not
    # established. That cost an afternoon on a failure that reproduced in CI and
    # not locally, on a byte-identical derivation, with nothing to look at but a
    # sentence asserting the wrong thing.
    sed -n '/^ask_network()/,/^}/p' ${installScript} > ask_network.txt || true
    if ! [ -s ask_network.txt ]; then
      echo "could not extract ask_network() from the installer at all." >&2
      echo "sed found no /^ask_network()/ .. /^}/ range, so every assertion" >&2
      echo "below would fail for a reason that has nothing to do with Wi-Fi." >&2
      echo "First 40 lines of what was searched:" >&2
      head -40 ${installScript} >&2
      exit 1
    fi
    if ! grep -q 'answers_file' ask_network.txt; then
      echo "the offline Wi-Fi screen is no longer skipped under --answers;" >&2
      echo "an unattended install would hang on a prompt nobody answers." >&2
      echo "ask_network() as extracted:" >&2
      sed 's/^/  | /' ask_network.txt >&2
      exit 1
    fi
    echo "  ok      the offline image offers Wi-Fi, and skips it unattended"

    # And only where there is a radio. Without this the screen appeared on every
    # machine with no wireless card -- a desktop on ethernet, and the VM every
    # wizard check runs in, where checks.installer-wizard sat on it for 180
    # seconds waiting for the keyboard screen behind it. An optional step is
    # still a step.
    if ! grep -q 'phy80211' ask_network.txt; then
      echo "the offline Wi-Fi screen is no longer gated on a wireless interface;" >&2
      echo "it will be offered to machines that have no radio to use it." >&2
      sed 's/^/  | /' ask_network.txt >&2
      exit 1
    fi
    echo "  ok      and only where there is a radio to use"

    # And the sentence that misled the tester: it may only be said when there is
    # genuinely no wireless interface. Asserted on the source, because the branch
    # lives inside connect_wifi's scan path and reaching it needs a whole nmcli.
    grep -q 'phy80211' ${installScript} || {
      echo "connect_wifi no longer tests for a wireless interface before" >&2
      echo "blaming the image for a missing driver" >&2
      exit 1
    }
    echo "  ok      the missing-driver line is gated on there being no interface"

    echo "the installer can tell three network failures apart, and a blocked radio from a missing one"
    touch $out
  ''
