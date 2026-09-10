{ pkgs, omarchy }:
# nixarchy-android's whole job is turning what the network says into a
# host:port, so the parsing IS the command -- everything else is prompting.
#
# avahi-browse and adb are stubbed, because the real ones need a phone with a
# pairing dialog open on a LAN, which no check can have. The stub output is
# real output: the field layout below was read off `avahi-browse -trp` on a
# live network, not from the man page, and the veth duplicates are what a
# machine running containers actually reports.
let
  # One phone, seen on wlan0 -- plus the noise a real machine produces. The
  # link-local AAAA and the veth repeats are the two things the awk exists to
  # drop, so they belong in the fixture rather than in a comment.
  connectRecords = ''
    +;wlan0;IPv4;Pixel;_adb-tls-connect._tcp;local
    =;wlan0;IPv4;Pixel;_adb-tls-connect._tcp;local;pixel.local;192.168.1.74;33811;
    =;wlan0;IPv6;Pixel;_adb-tls-connect._tcp;local;pixel.local;fe80::1c2d:3e4f:5a6b:7c8d;33811;
    =;veth51cabe5;IPv4;Pixel;_adb-tls-connect._tcp;local;pixel.local;192.168.1.74;33811;
    =;vethc5d5d93;IPv4;Pixel;_adb-tls-connect._tcp;local;pixel.local;192.168.1.74;33811;
  '';

  pairingRecords = ''
    =;wlan0;IPv4;Pixel;_adb-tls-pairing._tcp;local;pixel.local;192.168.1.74;41screwed;
  '';
in
pkgs.runCommand "nixarchy-android"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.coreutils
    ];
    connect = connectRecords;
    pairing = pairingRecords;
  }
  ''
    export HOME=$PWD/home
    mkdir -p "$HOME" "$PWD/stub"
    export PATH="$PWD/stub:$PATH"
    cmd=${omarchy}/share/omarchy/bin/nixarchy-android

    printf '%s' "$connect" > connect.txt
    printf '%s' "$pairing" > pairing.txt

    # The stub answers by service type, the way the real one does -- a stub
    # that ignores its arguments would let `find` pass while asking for the
    # wrong service entirely.
    cat > stub/avahi-browse <<'STUB'
    #!/bin/sh
    for a in "$@"; do
      case $a in
        _adb-tls-connect._tcp) cat "$RECORDS/connect.txt"; exit 0 ;;
        _adb-tls-pairing._tcp) cat "$RECORDS/pairing.txt"; exit 0 ;;
      esac
    done
    exit 0
    STUB
    sed -i 's/^    //' stub/avahi-browse
    chmod +x stub/avahi-browse
    export RECORDS=$PWD

    cat > stub/adb <<'STUB'
    #!/bin/sh
    case "$1" in
      devices) printf 'List of devices attached\n192.168.1.74:33811\tdevice\n\n' ;;
      connect) echo "connected to $2" ;;
      disconnect) echo "disconnected $2" ;;
      *) echo "adb stub: $*" ;;
    esac
    STUB
    sed -i 's/^    //' stub/adb
    chmod +x stub/adb

    # `got`, not `out`: $out is the derivation's output path, and a test that
    # assigns to it passes every assertion and then fails with "builder failed
    # to produce output path" -- which reads as a broken derivation rather
    # than a shadowed variable. Cost one build to find.
    fails=0
    want() {
      if printf '%s' "$2" | grep -q -- "$3"; then echo "  ok      $1"
      else
        echo "  FAILED  $1: no /$3/ in:"
        printf '%s\n' "$2" | sed 's/^/            /'
        fails=$((fails + 1))
      fi
    }
    reject() {
      if printf '%s' "$2" | grep -q -- "$3"; then
        echo "  FAILED  $1: /$3/ is in the output and should not be"
        printf '%s\n' "$2" | sed 's/^/            /'
        fails=$((fails + 1))
      else echo "  ok      $1"
      fi
    }

    echo "find:"
    got=$("$cmd" find 2>&1)
    want "reports the phone it can connect to" "$got" "192.168.1.74:33811"

    # The three noise cases, each asserted separately: together they would pass
    # if any one of them worked.
    reject "drops the link-local IPv6 record" "$got" "fe80"
    dupes=$(printf '%s\n' "$got" | grep -c "192.168.1.74:33811" || true)
    if [ "$dupes" = 1 ]; then echo "  ok      one phone is listed once, not once per veth"
    else
      echo "  FAILED  the phone is listed $dupes times; sort -u is not deduping"
      fails=$((fails + 1))
    fi
    want "says the pairing port is not the connect port" "$got" "changes each time"

    echo "list:"
    got=$("$cmd" list 2>&1)
    want "shows what adb has" "$got" "192.168.1.74:33811"

    echo "forget:"
    got=$("$cmd" forget 192.168.1.74:33811 2>&1)
    want "disconnects" "$got" "Disconnected"
    # It cannot revoke the phone's half, and saying so is the point: a command
    # called `forget` that leaves the phone still trusting this machine has to
    # admit it.
    want "admits the pairing lives on the phone" "$got" "revoke it"

    echo "refusals:"
    got=$("$cmd" forget 2>&1 || true)
    want "forget with no argument names the argument" "$got" "HOST:PORT"
    got=$("$cmd" nonsense 2>&1 || true)
    want "an unknown subcommand prints usage" "$got" "Usage: nixarchy android"

    echo "no phone on the network:"
    : > connect.txt
    : > pairing.txt
    got=$("$cmd" find 2>&1)
    want "says nothing is advertising" "$got" "No phone is advertising"
    want "and how to turn it on" "$got" "Wireless debugging"

    echo "adb missing:"
    # The catalogue row is the answer, and a "command not found" three frames
    # deeper is not.
    rm stub/adb
    got=$(PATH="$PWD/stub:/nonexistent-$RANDOM" "$cmd" list 2>&1 || true)
    want "names the package to install" "$got" "android-tools"

    [ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
    echo "all ok"
    touch $out
  ''
