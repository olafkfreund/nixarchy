{
  pkgs,
  location,
  omarchy,
}:
# The PACKAGED nixarchy-location (errexit and a declared PATH, which `bash
# pkgs/location.sh` would not have) against a private HOME and a fake nmcli.
# nmcli is an exported function: a declared runtimeInput beats a PATH stub.
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
    nmcli() { if [ -n "$NET" ]; then echo "ethernet:connected:Wired"; echo "wifi:connected:$NET"; else echo "ethernet:connected:Wired"; fi; }
    export -f nmcli
    export NET=""

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

    # a network name with a colon survives nmcli's escaping
    nmcli() { echo 'wifi:connected:Cafe\: Main'; }
    export -f nmcli
    $loc wifi link work
    eq "colon in the network name" "$(j '.wifi|keys' $s/places.json)" '["Cafe: Main"]'

    # a damaged places.json is reported, not overwritten
    echo 'not json' > $s/places.json
    if $loc set home X 2>/dev/null; then echo "  FAILED   wrote over a broken places.json"; fails=$((fails + 1)); fi
    eq "broken places.json untouched" "$(cat $s/places.json)" "not json"

    if [ "$fails" -gt 0 ]; then echo "$fails assertion(s) failed"; exit 1; fi
    echo "all assertions passed"
    touch $out
  ''
