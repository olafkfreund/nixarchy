{ pkgs, omarchy }:

pkgs.runCommand "nixarchy-stale-scripts"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
    ];
  }
  ''
    set -euo pipefail
    mkdir -p stub
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > stub/omarchy-pkg-add
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exec "$@"' > stub/setsid
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\n" "$*" > "$STUB_LOG"' > stub/uwsm-app
    chmod +x stub/*
    export PATH="$PWD/stub:$PATH"

    for entry in 'service-spotify spotify' 'service-signal signal-desktop' 'ai-chatgpt chatgpt'; do
      read -r script binary <<< "$entry"
      rm -f launch.log
      export STUB_LOG="$PWD/launch.log"
      bash ${omarchy}/share/omarchy/bin/omarchy-install-$script >/dev/null
      for attempt in $(seq 1 50); do
        [ -f launch.log ] && break
        sleep 0.1
      done
      [ -f launch.log ] || { echo "FAIL: $script never launched" >&2; exit 1; }
      actual=$(cat launch.log)
      [ "$actual" = "-- $binary" ] || {
        echo "FAIL: $script launched '$actual' instead of PATH command" >&2
        exit 1
      }
    done
    echo "stale-script installers launch PATH commands"

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > stub/agy
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\n" launched > "$AGENT_LOG"' > stub/omarchy-agent
    chmod +x stub/agy stub/omarchy-agent
    mkdir -p agent-home
    export HOME="$PWD/agent-home" AGENT_LOG="$PWD/agent.log"
    if ! bash ${omarchy}/share/omarchy/bin/omarchy-default-agent antigravity >/dev/null 2>&1; then
      echo "FAIL: Antigravity did not recognize agy" >&2
      exit 1
    fi
    [ "$(cat agent.log)" = launched ] || { echo "FAIL: Antigravity did not launch its agent" >&2; exit 1; }
    [ "$(cat agent-home/.config/omarchy/defaults/agent)" = antigravity ] || {
      echo "FAIL: Antigravity did not keep its menu id" >&2
      exit 1
    }
    echo "stale-script Antigravity recognizes agy"

    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'printf "%s\n" "$*" >> "$HYPR_LOG"' > stub/hyprctl
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > stub/gsettings
    chmod +x stub/hyprctl stub/gsettings
    export HYPR_LOG="$PWD/hypr.log" DBUS_SESSION_BUS_ADDRESS=stub
    bash ${omarchy}/share/omarchy/bin/omarchy-cursor-set >/dev/null
    hypr_calls=$(cat hypr.log)
    case "$hypr_calls" in
      *'eval hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")'*) ;;
      *) echo "FAIL: cursor did not update XCURSOR_THEME through Lua IPC" >&2; exit 1 ;;
    esac
    echo "stale-script cursor uses Lua IPC"
    touch "$out"
  ''
