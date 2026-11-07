{
  pkgs,
  installScript,
  removeScript,
}:

pkgs.runCommand "superwhisper-choice"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail
    mkdir -p stubs home
    printf '%s\n' \
      '#!${pkgs.runtimeShell}' \
      'name=$(basename "$0")' \
      'printf "%s %s\n" "$name" "$*" >> "$CALL_LOG"' \
      'case "$name" in' \
      '  hostname) echo testhost ;;' \
      '  nix) printf "%s\n" "''${NIX_STUB_UNFREE:-true}" ;;' \
      '  gum) if [[ $1 == choose ]]; then echo Offline; else [[ ''${GUM_STUB_DECLINE:-0} != 1 ]]; fi ;;' \
      '  nixarchy-apply) [[ ''${APPLY_STUB_FAIL:-0} != 1 ]] ;;' \
      '  systemctl) cp "$XDG_CONFIG_HOME/superwhisper/preferences.json" "$PREF_AT_START" ;;' \
      '  superwhisper) if [[ $1 == shortcuts && $2 == show ]]; then printf "%s\n" "{\"shortcuts\":{\"hold\":\"none\",\"toggle\":\"\"}}"; fi ;;' \
      '  omarchy-dictation-use) printf "%s\n" "$1" > "$XDG_CONFIG_HOME/omarchy/defaults/dictation" ;;' \
      '  omarchy-i18n) echo "$1" ;;' \
      'esac' > stubs/stub
    chmod +x stubs/stub
    for name in nix gum nixarchy-app-enable nixarchy-app-disable nixarchy-apply systemctl superwhisper \
      omarchy-dictation-use omarchy-restart-hyprctl omarchy-notification-send omarchy-i18n hostname; do
      ln -s stub "stubs/$name"
    done
    export PATH="$PWD/stubs:$PATH" HOME="$PWD/home" XDG_CONFIG_HOME="$PWD/home/config"
    export NIXARCHY_FLAKE=/test CALL_LOG="$PWD/calls" PREF_AT_START="$PWD/preferences-at-start"
    selection="$XDG_CONFIG_HOME/omarchy/defaults/dictation"
    preferences="$XDG_CONFIG_HOME/superwhisper/preferences.json"
    mkdir -p "$(dirname "$selection")" "$(dirname "$preferences")"
    fail() { echo "FAILED: $*" >&2; exit 1; }
    first() { grep -n "^$1 " "$CALL_LOG" | head -1 | cut -d: -f1; }

    export GUM_STUB_DECLINE=1
    bash ${installScript} --background >declined
    test ! -e "$preferences" && test ! -e "$selection" || fail 'declining wrote a file'
    ! grep -Eq '^(nixarchy-app-enable|nixarchy-apply) ' "$CALL_LOG" || fail 'declining enabled or applied'

    : > "$CALL_LOG"
    unset GUM_STUB_DECLINE
    printf '%s\n' '{"keep":"yes","errorLoggingEnabled":true}' > "$preferences"
    bash ${installScript} --background >agreed
    [ "$(first nixarchy-app-enable)" -lt "$(first nixarchy-apply)" ] || fail 'apply ran before enable'
    jq -e '.errorLoggingEnabled == false and .keep == "yes"' "$PREF_AT_START" >/dev/null 2>&1 || fail 'crash reports were not off when the unit started'
    jq -e '.errorLoggingEnabled == false and .keep == "yes"' "$preferences" >/dev/null || fail 'preferences lost a key or crash reports are on'
    grep -qx 'superwhisper models select offline' "$CALL_LOG" || fail 'the chosen mode was not applied'
    [ "$(cat "$selection")" = superwhisper ] || fail 'agreeing did not select superwhisper'

    : > "$CALL_LOG"
    rm "$selection"
    export APPLY_STUB_FAIL=1
    if bash ${installScript} --background >failed 2>&1; then echo 'failed apply succeeded' >&2; exit 1; fi
    test ! -e "$selection" || fail 'a failed rebuild wrote the selection'
    ! grep -q '^omarchy-dictation-use ' "$CALL_LOG" || fail 'a failed rebuild selected superwhisper'
    unset APPLY_STUB_FAIL

    : > "$CALL_LOG"
    export NIX_STUB_UNFREE=false
    bash ${installScript} --background >refused 2>&1
    grep -q 'allowUnfree = true' refused || fail 'unfree off did not say how to turn it on'
    test ! -e "$selection" || fail 'unfree off wrote the selection'
    ! grep -Eq '^(gum|nixarchy-app-enable|nixarchy-apply|systemctl) ' "$CALL_LOG" || fail 'unfree off asked or changed something'
    unset NIX_STUB_UNFREE

    : > "$CALL_LOG"
    printf '%s\n' superwhisper > "$selection"
    bash ${removeScript}
    test ! -e "$selection" || fail 'remove kept a superwhisper selection'
    [ "$(first nixarchy-app-disable)" -lt "$(first nixarchy-apply)" ] || fail 'remove applied before disabling'

    : > "$CALL_LOG"
    printf '%s\n' superwhisper > "$selection"
    export APPLY_STUB_FAIL=1
    if bash ${removeScript} >remove-failed 2>&1; then echo 'failed removal apply succeeded' >&2; exit 1; fi
    [ "$(cat "$selection" 2>/dev/null)" = superwhisper ] || fail 'a failed removal cleared the selection'
    unset APPLY_STUB_FAIL
    printf '%s\n' voxtype > "$selection"
    bash ${removeScript}
    [ "$(cat "$selection")" = voxtype ] || fail 'remove cleared a voxtype selection'
    echo 'superwhisper-choice: all cases pass'
    touch "$out"
  ''
