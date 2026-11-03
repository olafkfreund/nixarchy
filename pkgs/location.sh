# nixarchy-location -- Home, Work, and where I am now.
#
# weather.json (omarchy-weather-location's file, same format) is the current
# place: it existing means somebody chose it, a missing file means an IP guess.
# places.json beside it holds Home, Work and the Wi-Fi networks linked to them.
# Never touches the network.

dir=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/settings
weather=$dir/weather.json
places=$dir/places.json
coords='^(-?[0-9]+(\.[0-9]+)?),(-?[0-9]+(\.[0-9]+)?)$'
# The only keys weather.json may carry; null ones (no coordinates) are dropped.
keep='{name,latitude,longitude} | with_entries(select(.value != null))'

die() { echo "nixarchy-location: $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
usage: nixarchy-location [--json]
       nixarchy-location set home|work <name> [lat,lon]
       nixarchy-location now home|work|auto
       nixarchy-location wifi link home|work | wifi unlink <network>
       nixarchy-location apply
USAGE
}

# write <file> <json>: temporary file, then mv, so a reader never sees half of it.
write() {
  local tmp
  mkdir -p "$dir"
  tmp=$(mktemp "$1.XXXXXX")
  printf '%s\n' "$2" >"$tmp"
  mv "$tmp" "$1"
}

place_ok() { [[ ${1:-} == home || ${1:-} == work ]] || die "expected home or work, got '${1:-}'"; }

read_places() {
  [[ -f $places ]] || { echo '{}'; return 0; }
  jq -c 'if type == "object" then . else error("not an object") end' "$places" 2>/dev/null ||
    die "$places is not valid JSON; fix or remove it"
}

# A weather.json somebody picked before places.json existed becomes Home, once.
migrate() {
  local p new
  [[ -f $weather ]] || return 0
  p=$(read_places)
  new=$(jq -c --slurpfile w "$weather" '
    if .home or ($w[0] | type) != "object" or ($w[0].name | type) != "string" or $w[0].source == "wifi"
    then empty else .home = ($w[0] | '"$keep"') end' <<<"$p" 2>/dev/null) || true
  [[ -z $new ]] || write "$places" "$new"
}

# First connected Wi-Fi network's name (nmcli escapes ":" as "\:").
current_network() {
  local line
  while IFS= read -r line; do
    if [[ $line == wifi:connected:* ]]; then
      line=${line#wifi:connected:}
      echo "${line//\\:/:}"
      return 0
    fi
  done < <(nmcli -t -f TYPE,STATE,CONNECTION device 2>/dev/null || true)
}

show_json() {
  local w p
  w=$(jq -c 'select(type == "object")' "$weather" 2>/dev/null) || true
  [[ -n $w ]] || w=null
  p=$(read_places)
  jq -n --argjson w "$w" --argjson p "$p" '{
    now: (if $w == null then null else $w | '"$keep"' end),
    chosen: ($w != null),
    how: (if $w == null then "auto" elif $w.source == "wifi" then "wifi" else "picked" end),
    home: $p.home, work: $p.work}'
}

show() {
  show_json | jq -r '
    (if .chosen then "now:  \(.now.name // "?") (\(if .how == "wifi" then "set by Wi-Fi" else "picked" end))"
     else "now:  auto (guessed from the network)" end),
    "home: \(.home.name // "not set")", "work: \(.work.name // "not set")"'
}

cmd_set() {
  local entry p old cur coord=${3:-}
  place_ok "${1:-}"
  [[ -n ${2:-} ]] || die "a name is needed"
  if [[ -n $coord ]]; then
    [[ $coord =~ $coords ]] || die "invalid coordinates: $coord (expected lat,lon)"
    entry=$(jq -nc --arg n "$2" --argjson la "${coord%,*}" --argjson lo "${coord#*,}" '{name: $n, latitude: $la, longitude: $lo}')
  else
    entry=$(jq -nc --arg n "$2" '{name: $n}')
  fi
  p=$(read_places)
  # If weather.json holds this place's old value, it follows the edit (and keeps its source).
  old=$(jq -c --arg k "$1" ".[\$k] // empty | $keep" <<<"$p")
  cur=$(jq -c "$keep" "$weather" 2>/dev/null) || true
  write "$places" "$(jq -c --arg k "$1" --argjson e "$entry" '.[$k] = $e' <<<"$p")"
  if [[ -n $old && $old == "$cur" ]]; then
    write "$weather" "$(jq -c --argjson e "$entry" '{source} | with_entries(select(.value != null)) | $e + .' "$weather")"
  fi
}

cmd_now() {
  local e p
  case ${1:-} in
  auto) rm -f "$weather" ;;
  home | work)
    p=$(read_places)
    e=$(jq -c --arg k "$1" ".[\$k] // empty | $keep" <<<"$p")
    [[ -n $e ]] || die "$1 is not set"
    write "$weather" "$e"
    ;;
  *) die "expected home, work or auto, got '${1:-}'" ;;
  esac
}

# On a linked network: that place, marked "source":"wifi". Anywhere else: undo
# only what Wi-Fi wrote. A place somebody picked is never touched.
cmd_apply() {
  local net link="" e=""
  net=$(current_network)
  [[ -z $net ]] || link=$(read_places | jq -r --arg n "$net" '.wifi[$n] // empty')
  [[ -z $link ]] || e=$(read_places | jq -c --arg k "$link" ".[\$k] // empty | $keep | .source = \"wifi\"")
  if [[ -n $e ]]; then
    write "$weather" "$e"
  elif [[ -f $weather && $(jq -r '.source // empty' "$weather" 2>/dev/null || true) == wifi ]]; then
    rm -f "$weather"
  fi
}

cmd_wifi() {
  local net p
  case ${1:-} in
  link)
    place_ok "${2:-}"
    net=$(current_network)
    [[ -n $net ]] || die "not connected to Wi-Fi"
    p=$(read_places)
    jq -e --arg k "$2" '.[$k]' <<<"$p" >/dev/null || die "$2 is not set"
    write "$places" "$(jq -c --arg n "$net" --arg k "$2" '.wifi[$n] = $k' <<<"$p")"
    cmd_apply
    ;;
  unlink)
    [[ -n ${2:-} ]] || die "a network name is needed"
    p=$(read_places)
    write "$places" "$(jq -c --arg n "$2" 'del(.wifi[$n])' <<<"$p")"
    cmd_apply
    ;;
  *) die "expected link or unlink" ;;
  esac
}

case ${1:-} in
-h | --help) usage; exit 0 ;;
esac
migrate
case ${1:-} in
"") show; usage ;;
--json) show_json ;;
set) shift; cmd_set "$@" ;;
now) shift; cmd_now "$@" ;;
apply) cmd_apply ;;
wifi) shift; cmd_wifi "$@" ;;
*) usage >&2; exit 1 ;;
esac
