{ pkgs, ... }:
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
  isEdge = pkgs.lib.hasPrefix "edge-" shipped.version;
  # v4.5.0 names it install_chromium_extension and checks for Chromium first.
  extensionFunction = if isEdge then "install_browser_extension" else "install_chromium_extension";
in
pkgs.runCommand "nixarchy-webapp-browser"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.xdg-utils
    ];
    package = "${shipped}/share/omarchy";
  }
  ''
    set -euo pipefail
    root=$PWD
    mkdir -p "$root/bin" "$root/data/applications" "$root/empty-data" "$root/home"
    export HOME=$root/home XDG_DATA_HOME=$root/empty-data XDG_DATA_DIRS=$root/data
    export PATH=$root/bin:$PATH
    printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Chromium' 'Exec=chromium %U' > "$root/data/applications/chromium-browser.desktop"
    printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Firefox' 'Exec=firefox %u' > "$root/data/applications/firefox.desktop"

    printf '%s\n' '#!/bin/sh' 'cat "$BROWSER_DEFAULT"' > "$root/bin/omarchy-cmd-default-browser"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$root/bin/omarchy-cmd-browser-handoff"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$root/bin/omarchy-cmd-missing"
    # xdg-settings refuses an entry whose Exec= binary is not on PATH.
    for command in chromium firefox; do
      printf '%s\n' '#!/bin/sh' 'exit 0' > "$root/bin/$command"
    done
    for command in omarchy-notification-send omarchy-i18n; do
      printf '%s\n' '#!/bin/sh' 'exit 0' > "$root/bin/$command"
    done
    printf '%s\n' '#!/bin/sh' 'exec "$@"' > "$root/bin/setsid"
    printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "$@" > "$LAUNCH_LOG"' > "$root/bin/uwsm-app"
    printf '%s\n' '#!/bin/sh' 'echo "sudo was called" >> "$SUDO_LOG"; exit 1' > "$root/bin/sudo"
    chmod +x "$root/bin/"*

    launcher=$package/bin/omarchy-launch-webapp
    for browser in chromium-browser.desktop firefox.desktop; do
      printf '%s\n' "$browser" > "$root/default"
      export BROWSER_DEFAULT=$root/default LAUNCH_LOG=$root/launch.log
      rm -f "$LAUNCH_LOG"
      bash "$launcher" https://example.com || { echo "FAILED webapp default $browser: launcher exited" >&2; exit 1; }
      printf '%s\n' '--' 'chromium' '--app=https://example.com' > "$root/expected"
      cmp "$root/expected" "$LAUNCH_LOG" || { echo "FAILED webapp default $browser: wrong command" >&2; exit 1; }
    done

    installer=$package/bin/omarchy-install-service-1password
    sed -n '/^${extensionFunction}() {/,/^}/p' "$installer" > "$root/extension-function"
    grep -q '^${extensionFunction}() {' "$root/extension-function" || { echo 'FAILED P4: function missing' >&2; exit 1; }
    export SUDO_LOG=$root/sudo.log
    EXTENSION_ID=aeblfdkhhhdcdjpifhhbdiojplfjncoa
    source "$root/extension-function"
    ${extensionFunction} > "$root/extension.out" 2>&1 || { echo 'FAILED P4: function exited nonzero' >&2; exit 1; }
    grep -qF 'programs.chromium.extensions' "$root/extension.out" || { echo 'FAILED P4: declarative message missing' >&2; exit 1; }
    [[ ! -e $SUDO_LOG ]] || { echo 'FAILED P4: sudo was called' >&2; exit 1; }

    ${
      if isEdge then
        ''
          provision=$package/bin/omarchy-provision-user
          awk '/^\. .*nixarchy-store-owned\.sh$/ { copying=1 } copying { print; if (/^[[:space:]]*xdg-mime default omarchy-HEY.desktop/) mailto=1; else if (mailto && /^[[:space:]]*fi$/) exit }' "$provision" > "$root/provision-block"
          grep -q 'xdg-mime default omarchy-HEY.desktop' "$root/provision-block" || { echo 'FAILED provisioning: patched block missing' >&2; exit 1; }
          export XDG_CONFIG_HOME=$root/config XDG_CURRENT_DESKTOP= BROWSER=
          mkdir -p "$XDG_CONFIG_HOME"

          source "$root/provision-block"
          [[ $(env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser) == chromium-browser.desktop ]] || {
            echo 'FAILED provisioning: empty config did not select Chromium' >&2; exit 1;
          }

          printf '%s\n' '[Default Applications]' 'x-scheme-handler/http=firefox.desktop' 'x-scheme-handler/https=firefox.desktop' > "$XDG_CONFIG_HOME/mimeapps.list"
          source "$root/provision-block"
          [[ $(env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser) == firefox.desktop ]] || {
            echo 'FAILED provisioning: regular Firefox default changed' >&2; exit 1;
          }

          rm "$XDG_CONFIG_HOME/mimeapps.list"
          ln -s ${pkgs.writeText "nixarchy-webapp-store-mimeapps" "[Default Applications]\n"} "$XDG_CONFIG_HOME/mimeapps.list"
          target=$(readlink "$XDG_CONFIG_HOME/mimeapps.list")
          source "$root/provision-block"
          [[ -L $XDG_CONFIG_HOME/mimeapps.list && $(readlink "$XDG_CONFIG_HOME/mimeapps.list") == "$target" ]] || {
            echo 'FAILED provisioning: store link changed' >&2; exit 1;
          }
          [[ -z $(env -u BROWSER XDG_CURRENT_DESKTOP= xdg-settings get default-web-browser) ]] || {
            echo 'FAILED provisioning: store-owned browser default changed' >&2; exit 1;
          }
        ''
      else
        ''
          echo 'SKIP provisioning: stable pin retains its existing provisioning behavior'
        ''
    }

    touch "$out"
  ''
