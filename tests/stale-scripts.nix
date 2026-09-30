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
    touch "$out"
  ''
