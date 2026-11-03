{
  inputs,
  pkgs,
  location,
  omarchy,
}:
# The PACKAGED nixarchy-location (errexit and a declared PATH, which `bash
# pkgs/location.sh` would not have) against a private HOME and a fake nmcli.
# nmcli is an exported function: a declared runtimeInput beats a PATH stub.
let
  # The module's unit, evaluated: it must run `watch` by store path and
  # restart on failure.
  unit =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules = [
        inputs.self.nixosModules.nixarchy
        inputs.home-manager.nixosModules.home-manager
        {
          programs.nixarchy = {
            enable = true;
            user = "someone";
          };
          users.users.someone = {
            isNormalUser = true;
            home = "/home/someone";
          };
          home-manager.users.someone = {
            imports = [ inputs.self.homeManagerModules.nixarchy ];
            programs.nixarchy.enable = true;
            home.stateVersion = "25.05";
          };
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config.home-manager.users.someone.systemd.user.services.nixarchy-location-watch;
in
assert pkgs.lib.assertMsg (
  unit.Service.ExecStart == [ "${location}/bin/nixarchy-location watch" ]
  && unit.Service.Restart == "on-failure"
  && unit.Service.RestartSec == 30
  && unit.Install.WantedBy == [ "graphical-session.target" ]
) "nixarchy-location-watch unit is wrong: ${builtins.toJSON unit}";
pkgs.runCommand "nixarchy-location-runs"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail
    export HOME=$TMPDIR/home
    unset XDG_STATE_HOME
    s=$HOME/.local/state/omarchy/settings
    mkdir -p "$s"
    loc=${location}/bin/nixarchy-location
    # HASWIFI: a Wi-Fi device exists. MON: what `nmcli -t monitor` prints, one
    # line per entry; the sample lines are NetworkManager's own wording.
    nmcli() {
      case "$*" in
        "-t monitor") [ -z "$FLIP" ] || echo "$FLIP" >"$TMPDIR/flip"; printf '%b' "$MON" ;;
        "-t -f TYPE device") echo ethernet; [ -z "$HASWIFI" ] || echo wifi ;;
        *) n=$NET; [ ! -e "$TMPDIR/flip" ] || n=$(cat "$TMPDIR/flip")
           echo "ethernet:connected:Wired"; [ -z "$n" ] || echo "wifi:connected:$n" ;;
      esac
    }
    export -f nmcli
    export NET="" HASWIFI=1 MON=""

    fails=0
    eq() { # eq <what> <got> <want>
      if [ "$2" = "$3" ]; then echo "  ok       $1"; else echo "  FAILED   $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
    }
    j() { jq -c "$1" "$2"; }

    # nothing set: an IP guess
    eq "nothing chosen" "$($loc --json | jq -c '[.chosen,.how,.now]')" '[false,"auto",null]'

    # set / now / --json round trip
    $loc set home Lisbon 38.72,-9.14
    $loc set work "Porto"
    eq "home stored" "$(j .home $s/places.json)" '{"name":"Lisbon","latitude":38.72,"longitude":-9.14}'
    eq "set alone chooses nothing" "$([ -e $s/weather.json ] && echo yes || echo no)" no
    $loc now home
    eq "now home writes weather.json" "$(j . $s/weather.json)" '{"name":"Lisbon","latitude":38.72,"longitude":-9.14}'
    eq "json: picked" "$($loc --json | jq -c '[.chosen,.how,.now.name,.home.name,.work.name]')" '[true,"picked","Lisbon","Lisbon","Porto"]'
    $loc now work
    eq "work has no coordinates" "$(j . $s/weather.json)" '{"name":"Porto"}'
    $loc now auto
    eq "now auto removes the file" "$([ -e $s/weather.json ] && echo yes || echo no)" no

    # set follows weather.json when it holds the place's old value
    $loc set home Lisbon 38.72,-9.14; $loc now home
    $loc set home Faro 37.02,-7.93
    eq "set follows a picked place" "$(j . $s/weather.json)" '{"name":"Faro","latitude":37.02,"longitude":-7.93}'
    $loc set home Lisbon 38.72,-9.14
    jq -c '. + {source:"wifi"}' $s/weather.json > $s/w.tmp && mv $s/w.tmp $s/weather.json
    $loc set home Faro2
    eq "set follows a wifi place and keeps its source" "$(j . $s/weather.json)" '{"name":"Faro2","source":"wifi"}'
    $loc set home Lisbon 38.72,-9.14
    $loc now work
    $loc set home Other
    eq "set leaves another place alone" "$(j . $s/weather.json)" '{"name":"Porto"}'
    $loc set home Lisbon 38.72,-9.14; $loc now auto

    # the upstream command still reads what we wrote
    export PATH=${omarchy}/share/omarchy/bin:${pkgs.jq}/bin:$PATH
    $loc now home
    eq "omarchy-weather-location reads it" "$(omarchy-weather-location)" Lisbon

    # a bad coordinate is refused and nothing changes
    before=$(cat $s/places.json)
    if $loc set home Nowhere 91,abc 2>/dev/null; then echo "  FAILED   bad coordinates accepted"; fails=$((fails + 1)); fi
    eq "bad coordinates leave places.json alone" "$(cat $s/places.json)" "$before"
    if $loc now work-typo 2>/dev/null; then echo "  FAILED   bad place accepted"; fails=$((fails + 1)); fi

    # migration: a weather.json picked before places.json existed becomes Home, once
    rm -f $s/places.json
    printf '%s\n' '{"name":"Oslo","latitude":59.9,"longitude":10.7}' > $s/weather.json
    $loc --json >/dev/null
    eq "migrated into home" "$(j .home $s/places.json)" '{"name":"Oslo","latitude":59.9,"longitude":10.7}'
    $loc set home Bergen
    printf '%s\n' '{"name":"Elsewhere"}' > $s/weather.json
    $loc --json >/dev/null
    eq "migration happens once" "$(j .home.name $s/places.json)" '"Bergen"'
    rm -f $s/places.json
    printf '%s\n' '{"name":"Cafe","source":"wifi"}' > $s/weather.json
    $loc --json >/dev/null
    eq "a wifi-written file is not a Home" "$([ -e $s/places.json ] && echo yes || echo no)" no

    # apply
    rm -f $s/weather.json $s/places.json
    $loc set home Lisbon 38.72,-9.14
    $loc set work Porto
    NET="Casa Wi-Fi"
    $loc wifi link home
    eq "link applies at once" "$(j . $s/weather.json)" '{"name":"Lisbon","latitude":38.72,"longitude":-9.14,"source":"wifi"}'
    eq "link stored by network" "$(j .wifi $s/places.json)" '{"Casa Wi-Fi":"home"}'
    NET="Hotspot"; $loc apply
    eq "unlinked network clears a wifi place" "$([ -e $s/weather.json ] && echo yes || echo no)" no
    $loc now work; NET="Hotspot"; $loc apply
    eq "unlinked network leaves a picked place" "$(j . $s/weather.json)" '{"name":"Porto"}'
    NET="Casa Wi-Fi"; $loc apply
    eq "linked network overrides with source wifi" "$(j .source $s/weather.json)" '"wifi"'
    NET=""; $loc apply
    eq "off Wi-Fi clears a wifi place" "$([ -e $s/weather.json ] && echo yes || echo no)" no
    NET="Casa Wi-Fi"; $loc apply
    $loc wifi unlink "Casa Wi-Fi"
    eq "unlink clears and forgets" "$([ -e $s/weather.json ] && echo yes || echo no) $(j '.wifi|length' $s/places.json)" "no 0"
    NET=""
    if $loc wifi link home 2>/dev/null; then echo "  FAILED   link without Wi-Fi accepted"; fails=$((fails + 1)); fi

    # watch: no Wi-Fi device -> exits 0 and applies nothing
    rm -f $s/weather.json $s/places.json
    $loc set home Lisbon 38.72,-9.14
    NET="Casa Wi-Fi"; $loc wifi link home; rm -f $s/weather.json
    HASWIFI="" $loc watch; rc=$?
    eq "watch: no Wi-Fi device exits 0" "$rc $([ -e $s/weather.json ] && echo applied || echo idle)" "0 idle"
    # watch: applies at start, again on a connection event, and exits 1 when the monitor ends
    rc=0; MON="Networkmanager is now in the 'connecting' state\nwlan0: connecting (prepare)\n" $loc watch 2>/dev/null || rc=$?
    eq "watch: applies once at start; monitor ending is a failure" "$rc $(j .source $s/weather.json)" '1 "wifi"'
    # the sample lines of a connection change: the network changes when the monitor
    # starts, so only the event-triggered apply (one, for the whole burst) can see it
    rm -f $s/weather.json "$TMPDIR/flip"; NET="Hotspot"
    rc=0; FLIP="Casa Wi-Fi" MON="wlan0: disconnected\nwlan0: using connection 'Casa Wi-Fi'\nwlan0: connected\n'Casa Wi-Fi' is now the primary connection\nConnectivity is now 'full'\n" $loc watch 2>/dev/null || rc=$?
    eq "watch: a connection event re-applies" "$rc $(j .name $s/weather.json)" '1 "Lisbon"'
    # lines that are not connection changes do not
    rm -f $s/weather.json "$TMPDIR/flip"
    rc=0; FLIP="Casa Wi-Fi" MON="wlan0: device state change\nsomething else\n" $loc watch 2>/dev/null || rc=$?
    eq "watch: unrelated lines do not apply" "$rc $([ -e $s/weather.json ] && echo applied || echo idle)" "1 idle"
    rm -f "$TMPDIR/flip"; NET=""
    $loc set work Porto

    # a network name with a colon survives nmcli's escaping
    nmcli() { echo 'wifi:connected:Cafe\: Main'; }
    export -f nmcli
    $loc wifi link work
    eq "colon in the network name" "$(j '.wifi|keys' $s/places.json)" '["Cafe: Main","Casa Wi-Fi"]'

    # a damaged places.json is reported, not overwritten
    echo 'not json' > $s/places.json
    if $loc set home X 2>/dev/null; then echo "  FAILED   wrote over a broken places.json"; fails=$((fails + 1)); fi
    eq "broken places.json untouched" "$(cat $s/places.json)" "not json"

    if [ "$fails" -gt 0 ]; then echo "$fails assertion(s) failed"; exit 1; fi
    echo "all assertions passed"
    touch $out
  ''
