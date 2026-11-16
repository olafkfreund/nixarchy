{
  lib,
  writeShellApplication,
  coreutils,
  gnugrep,
  jq,
}:
{
  publisher,
  t3,
  theme,
  timeoutSecs ? 30,
  killSecs ? 5,
}:
writeShellApplication {
  name = "nixarchy-t3code-theme";
  runtimeInputs = [
    coreutils
    gnugrep
    jq
    publisher
    t3
  ];
  bashOptions = [ "nounset" ];
  text = ''
    log() {
      printf 't3code-theme: %s\n' "$1" >&2
    }

    if [ -z "''${HOME:-}" ]; then
      log 'HOME unset'
      exit 0
    fi

    export T3CODE_HOME="$HOME/.t3"
    STATE="$T3CODE_HOME/userdata"

    for name in omarchy-theme-set-t3code t3; do
      if ! command -v "$name" >/dev/null 2>&1; then
        log "$name not found"
        exit 0
      fi
    done

    if [ ! -f "$HOME/.local/state/omarchy/current/theme/t3code.json" ]; then
      log 'no Omarchy palette staged yet; next activation retries'
      exit 0
    fi

    mkdir -p "$STATE"
    if omarchy-theme-set-t3code; then
      if grep -qF '{{' "$HOME/.local/state/omarchy/current/theme/t3code.json"; then
        log 'palette has unresolved colours; kept the previous one'
      fi
    else
      status=$?
      log "publisher exited $status"
      exit 0
    fi

    theme=${lib.escapeShellArg (if theme == null then "" else theme)}
    if [ -z "$theme" ]; then
      log 'publish only'
      exit 0
    fi

    want="$theme"
    if [ ! -f "$STATE/themes/$want.json" ]; then
      if [ "$want" != omarchy ] && [ -f "$STATE/themes/omarchy.json" ]; then
        log "theme $want not published; using omarchy"
        want=omarchy
      else
        log "theme $want not published"
        exit 0
      fi
    fi

    currentTheme=$(jq -r '.defaultTheme // empty' "$STATE/settings.json" 2>/dev/null)
    if [ "$currentTheme" = "$want" ]; then
      exit 0
    fi

    output=$(mktemp) || {
      log 'could not create output file'
      exit 0
    }
    if timeout -k ${toString killSecs} ${toString timeoutSecs} t3 theme set "$want" --base-dir "$T3CODE_HOME" >"$output" 2>&1; then
      :
    else
      status=$?
      log "t3 theme set exited $status"
      tail -n 5 "$output" | while IFS= read -r line || [ -n "$line" ]; do
        log "$line"
      done
    fi
    rm -f "$output"
    exit 0
  '';
}
