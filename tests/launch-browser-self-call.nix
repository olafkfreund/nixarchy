{ pkgs, omarchy }:
# #1342: omarchy-launch-browser refuses a default browser entry that runs the
# launcher itself. 4.0.4 met 4.0.5's mimeapps list and recursed without bound.
# The fixture is that entry (`Exec=omarchy-launch-browser`); the wrapper on PATH
# counts calls and stops the chain at 20 so a missing guard fails rather than
# hangs. The control is the built launcher with the guard deleted: it must
# recurse, or this check cannot see the bug (CLAUDE.md section 1).
pkgs.runCommand "nixarchy-launch-browser-self-call"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    root=$PWD
    export HOME=$root/home
    mkdir -p home/.local/share/applications bin
    printf '%s\n' '[Desktop Entry]' 'Exec=omarchy-launch-browser %U' > home/.local/share/applications/omarchy-browser.desktop

    printf '%s\n' '#!/bin/sh' 'echo omarchy-browser.desktop' > bin/omarchy-cmd-default-browser
    printf '%s\n' '#!/bin/sh' "echo \"\$@\" >> $root/notified" > bin/omarchy-notification-send
    printf '%s\n' '#!/bin/sh' "echo \"\$@\" >> $root/spawned" > bin/systemd-run
    printf '%s\n' '#!/bin/sh' "echo \"\$@\" >> $root/spawned" > bin/uwsm-app
    printf '%s\n' '#!/bin/sh' 'exit 1' > bin/omarchy-cmd-browser-handoff
    printf '%s\n' '#!/bin/sh' \
      "n=\$(cat $root/count 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > $root/count" \
      '[ "$n" -ge 20 ] && exit 99' \
      'exec bash "$LAUNCHER" "$@"' > bin/omarchy-launch-browser
    chmod +x bin/*
    export PATH=$root/bin:$PATH

    launcher=${omarchy}/share/omarchy/bin/omarchy-launch-browser
    run() {
      rm -f count notified spawned
      status=0
      LAUNCHER=$1 timeout 60 omarchy-launch-browser https://example.org > run.out 2>&1 || status=$?
    }

    # patched: one call, a notification naming #1342, exit 1
    grep -qF 'itself (#1342)' "$launcher" || { echo "the built launcher carries no guard" >&2; exit 1; }
    run "$launcher"
    [ "$status" = 1 ] || { echo "patched launcher exited $status, wanted 1: $(cat run.out)" >&2; exit 1; }
    [ "$(cat count)" = 1 ] || { echo "patched launcher called itself $(cat count) times" >&2; exit 1; }
    grep -qF '#1342' notified || { echo "no notification named #1342" >&2; exit 1; }
    echo "  ok      the guard stops the self-call and says why"

    # control: the same launcher with the guard deleted recurses
    sed '/^if \[\[ .*omarchy-launch-browser \]\]; then$/,/^fi$/d' "$launcher" > unguarded.sh
    if grep -qF 'itself (#1342)' unguarded.sh; then
      echo "the sed did not remove the guard, so the control proves nothing" >&2; exit 1
    fi
    run "$root/unguarded.sh"
    [ "$(cat count)" = 20 ] || {
      echo "the control did not recurse, so this check cannot see #1342 (count $(cat count))" >&2; exit 1
    }
    echo "  ok      without the guard the same fixture recurses to its cap"
    touch $out
  ''
