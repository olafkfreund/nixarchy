{ pkgs, renderedInstallScript }:
# Exercise the installer that users run, including its build-time substitutions.
pkgs.runCommand "nixarchy-installer-input-validation"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    set -uo pipefail
    script=${renderedInstallScript}
    funcs=functions.sh
    : > "$funcs"
    grep '^RESERVED_USERS=' "$script" >> "$funcs" || { echo 'FAILED rendered RESERVED_USERS missing'; exit 1; }
    for fn in validate_username validate_hostname validate_timezone validate_keymap validate_answers wifi_networks connect_wifi generate_hardware_config; do
      sed -n "/^$fn()/,/^}/p" "$script" >> "$funcs"
      grep -q "^$fn()" "$funcs" || { echo "FAILED rendered $fn missing"; exit 1; }
    done

    cat > exercise.sh <<'EOF'
    set -uo pipefail
    . ./functions.sh
    failures=0
    ok() { echo "ok $1"; }
    fail() { echo "FAILED $1"; failures=$((failures + 1)); }
    accept() { local label=$1 fn=$2 value=$3; if "$fn" "$value" >msg 2>&1; then ok "$label"; else fail "$label: $(cat msg)"; fi; }
    refuse() { local label=$1 fn=$2 value=$3; if "$fn" "$value" >msg 2>&1; then fail "$label accepted"; else ok "$label"; fi; }

    RESERVED_USERS=''${RESERVED_USERS:-}
    accept 'normal reference username' validate_username omarchy
    refuse 'evaluated messagebus account' validate_username messagebus
    refuse 'extra daemon account' validate_username daemon
    accept '32-byte username' validate_username "$(printf 'a%.0s' {1..32})"
    refuse '33-byte username' validate_username "$(printf 'a%.0s' {1..33})"
    accept '63-byte hostname' validate_hostname "$(printf 'a%.0s' {1..63})"
    refuse '64-byte hostname' validate_hostname "$(printf 'a%.0s' {1..64})"

    TZDIR=$PWD/zones KEYMAPS=$PWD/keymaps
    mkdir -p "$TZDIR/Europe" "$KEYMAPS/i386/qwerty"
    printf 'TZif fixture' > "$TZDIR/UTC"
    printf 'Zone table\n' > "$TZDIR/zone.tab"
    : > "$KEYMAPS/i386/qwerty/us.map.gz"
    accept 'TZif zone file' validate_timezone UTC
    refuse 'timezone directory' validate_timezone Europe
    refuse 'zone.tab is not TZif' validate_timezone zone.tab
    refuse 'timezone traversal' validate_timezone ../outside
    accept 'literal keymap' validate_keymap us
    refuse 'wildcard keymap' validate_keymap 'u*'
    grep -Fq 'validate_timezone "$timezone"' "$script" || fail 'answers do not call timezone validator'
    grep -Fq 'validate_keymap "$keymap"' "$script" || fail 'answers do not call keymap validator'

    ui_screen() { :; }
    ui_left() { :; }
    ui_widget_height() { echo 10; }
    ui_gum_pad() { echo 0; }
    wifi_block() { echo none; }
    gum() { if [ "$1" = choose ]; then head -1; else echo; fi; }
    nmcli() {
      if [ "$1" = radio ]; then return 0; fi
      if [ "$1" = -t ]; then
        if [ "$2" = -e ] && [ "$3" = no ] && [ "$4" = -f ] && [ "$5" = SIGNAL,SECURITY,SSID ]; then
          printf '70:WPA2:%s\n' "$wanted_ssid"
        else
          case $wanted_ssid in
            'Cafe:Guest') printf 'Cafe\\:Guest:70:WPA2\n' ;;
            *) printf 'Cafe\\\\Guest:70:WPA2\n' ;;
          esac
        fi
        return 0
      fi
      if [ "$1" = device ]; then printf '%s' "$4" > connected; return 0; fi
      return 1
    }
    for wanted_ssid in 'Cafe:Guest' 'Cafe\Guest'; do
      rm -f connected
      if connect_wifi >wifi.out 2>&1 && [ -f connected ] && [ "$(cat connected)" = "$wanted_ssid" ]; then
        ok "SSID $wanted_ssid reaches connect unchanged"
      else
        fail "SSID $wanted_ssid did not reach connect unchanged: $(cat connected 2>/dev/null || true)"
      fi
    done

    hostdir=$PWD/host
    mkdir -p "$hostdir"
    nixos-generate-config() { echo '{}'; }
    reuse_baked_initrd() { return 0; }
    write_hardware_modules() { return 1; }
    if generate_hardware_config >hardware.out 2>&1; then
      fail 'hardware module write failure was swallowed'
    elif grep -Fq "$hostdir/nixarchy-hardware.nix" hardware.out; then
      ok 'hardware module write failure stops with destination'
    else
      fail 'hardware module failure did not name destination'
    fi
    write_hardware_modules() { echo '{}' > "$1"; }
    if generate_hardware_config >hardware.out 2>&1; then ok 'hardware module write succeeds'; else fail 'hardware module successful write refused'; fi

    [ "$failures" -eq 0 ] || exit 1
    touch "$out"
    EOF
    bash exercise.sh
  ''
