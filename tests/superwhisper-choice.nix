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

    export GUM_STUB_DECLINE=1
    bash ${installScript} --background >declined
    test ! -e "$preferences" && test ! -e "$selection"
    ! grep -Eq '^(nixarchy-app-enable|nixarchy-apply) ' "$CALL_LOG"

    : > "$CALL_LOG"
    unset GUM_STUB_DECLINE
    printf '%s\n' '{"keep":"yes","errorLoggingEnabled":true}' > "$preferences"
    bash ${installScript} --background >agreed
    test "$(grep -n '^nixarchy-app-enable ' "$CALL_LOG" | cut -d: -f1)" -lt \
      "$(grep -n '^nixarchy-apply ' "$CALL_LOG" | cut -d: -f1)"
    jq -e '.errorLoggingEnabled == false and .keep == "yes"' "$PREF_AT_START" >/dev/null
    jq -e '.errorLoggingEnabled == false and .keep == "yes"' "$preferences" >/dev/null
    grep -qx 'superwhisper models select offline' "$CALL_LOG"
    test "$(cat "$selection")" = superwhisper

    : > "$CALL_LOG"
    rm "$selection"
    export APPLY_STUB_FAIL=1
    if bash ${installScript} --background >failed 2>&1; then echo 'failed apply succeeded' >&2; exit 1; fi
    test ! -e "$selection"
    ! grep -q '^omarchy-dictation-use ' "$CALL_LOG"
    unset APPLY_STUB_FAIL

    : > "$CALL_LOG"
    export NIX_STUB_UNFREE=false
    bash ${installScript} --background >refused 2>&1
    grep -q 'allowUnfree = true' refused
    test ! -e "$selection"
    ! grep -Eq '^(gum|nixarchy-app-enable|nixarchy-apply|systemctl) ' "$CALL_LOG"
    unset NIX_STUB_UNFREE

    : > "$CALL_LOG"
    printf '%s\n' superwhisper > "$selection"
    bash ${removeScript}
    test ! -e "$selection"
    test "$(grep -n '^nixarchy-app-disable ' "$CALL_LOG" | cut -d: -f1)" -lt \
      "$(grep -n '^nixarchy-apply ' "$CALL_LOG" | cut -d: -f1)"

    : > "$CALL_LOG"
    printf '%s\n' superwhisper > "$selection"
    export APPLY_STUB_FAIL=1
    if bash ${removeScript} >remove-failed 2>&1; then echo 'failed removal apply succeeded' >&2; exit 1; fi
    test "$(cat "$selection")" = superwhisper
    unset APPLY_STUB_FAIL
    printf '%s\n' voxtype > "$selection"
    bash ${removeScript}
    test "$(cat "$selection")" = voxtype
    touch "$out"
  ''
