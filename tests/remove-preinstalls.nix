{ inputs, pkgs }:
# Remove and Restore preinstalls delete only what Omarchy seeded (#1304).
#
# Upstream's Remove deleted every web app and TUI launcher and rm -f'd named
# ~/.local/bin entries, whoever made them -- a user's own launcher, a
# home-manager link, a hand-written wrapper. This runs the replacement scripts
# against a fixture home that holds both kinds, and compares the whole tree
# before and after, so a deletion nobody thought to assert on still shows.
#
# The scripts run only inside $TMPDIR/home. checks.menu-actions cannot see this
# (an rm through a variable is its documented blind spot), so this is the check
# that says the deletions are the right ones.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-remove-preinstalls"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
    ];
    tree = "${shipped}/share/omarchy";
    upstream = inputs.omarchy;
    remove = "${shipped}/share/omarchy/bin/omarchy-remove-preinstalls";
    restore = "${shipped}/share/omarchy/bin/omarchy-install-preinstalls";
    shell = pkgs.runtimeShell;
  }
  ''
    set -euo pipefail
    export LC_ALL=C
    real_home=$HOME
    export HOME=$TMPDIR/home
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_CACHE_HOME=$HOME/.cache
    export OMARCHY_PATH=$tree

    A=$HOME/.local/share/applications
    B=$HOME/.local/bin
    HM=$TMPDIR/hm
    mkdir -p "$A" "$B" "$HM" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

    # Stubs: record the call and succeed, except the two that must not.
    mkdir -p "$TMPDIR/stubs"
    for n in gum hyprctl update-desktop-database; do
      printf '#!%s\necho "%s $*" >> "$TMPDIR/calls"\nexit 0\n' "$shell" "$n" > "$TMPDIR/stubs/$n"
    done
    printf '#!%s\necho "omarchy-install-hermes-cli $*" >> "$TMPDIR/calls"\nexit 1\n' "$shell" > "$TMPDIR/stubs/omarchy-install-hermes-cli"
    printf '#!%s\necho "pacman: not on NixOS" >&2\nexit 1\n' "$shell" > "$TMPDIR/stubs/pacman"
    chmod +x "$TMPDIR"/stubs/*
    export PATH=$TMPDIR/stubs:$tree/bin:$PATH

    # Fixture. Seeds Omarchy wrote, and things it did not (including home/.local/bin/gh).
    cp --no-preserve=mode "$tree/applications/YouTube.desktop" "$A/"
    cp --no-preserve=mode "$tree/applications/mpv.desktop" "$A/"
    sed 's|https://launchpad.37signals.com|https://example.org/bc|' "$tree/applications/Basecamp.desktop" > "$A/Basecamp.desktop"
    printf '[Desktop Entry]\nName=MyApp\nExec=omarchy-launch-webapp https://example.org\n' > "$A/MyApp.desktop"
    printf '[Desktop Entry]\nName=MyTui\nExec=xdg-terminal-exec --app-id=TUI.mytui -e htop\n' > "$A/MyTui.desktop"
    cp --no-preserve=mode "$tree/applications/Zoom.desktop" "$HM/Zoom.desktop"
    ln -s "$HM/Zoom.desktop" "$A/Zoom.desktop"

    printf '#!/bin/bash\nexec /opt/gh "$@"\n' > "$B/gh"

    state() {
      (cd "$TMPDIR" && find home hm \( -type f -o -type l \) -print0 | sort -z) |
        while IFS= read -r -d "" p; do
          if [ -L "$TMPDIR/$p" ]; then
            printf '%s\tL %s\n' "$p" "$(readlink "$TMPDIR/$p")"
          else
            printf '%s\tF %s\n' "$p" "$(sha256sum <"$TMPDIR/$p" | cut -d" " -f1)"
          fi
        done
    }
    # D/C/A<TAB>path, one per line, sorted: deleted, changed, added.
    compare() {
      awk -F '\t' 'NR == FNR { b[$1] = $2; next } { a[$1] = $2 }
        END {
          for (p in b) if (!(p in a)) print "D\t" p; else if (b[p] != a[p]) print "C\t" p
          for (p in a) if (!(p in b)) print "A\t" p
        }' "$1" "$2" | sort
    }
    pick() { grep "^$1"$'\t' "$2" | cut -f2- || true; }  # paths of one kind, one per line
    join() { paste -sd' ' || true; }

    fails=()
    fail() { fails+=("$1"); }
    report() {
      if [ "''${#fails[@]}" -gt 0 ]; then
        printf 'FAIL: %s\n' "''${fails[@]}" >&2
        exit 1
      fi
    }

    # ---- Remove ----
    state > before
    rc=0
    bash "$remove" > remove.log 2>&1 || rc=$?
    state > after
    compare before after > delta

    [ "$rc" -eq 0 ] || fail "remove exited $rc"
    want=$(printf '%s\n' home/.local/share/applications/YouTube.desktop | sort)
    got=$(pick D delta)
    extra=$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | join)
    left=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | join)
    [ -z "$extra" ] || fail "deleted files that are not preinstalls: $extra"
    [ -z "$left" ] || fail "left preinstalls in place: $left"
    changed=$(pick C delta | join)
    [ -z "$changed" ] || fail "changed files it should not touch: $changed"
    added=$(pick A delta | join)
    [ "$added" = "home/.local/state/omarchy/preinstalls-removed" ] || fail "wrote unexpected files: $added"
    [ ! -e "$real_home" ] || fail "wrote outside the fixture: $real_home"
    if [ "''${#fails[@]}" -gt 0 ]; then cat remove.log >&2; fi
    report
    echo "remove: deleted only $(pick D delta | join)"

    # ---- Restore, from that end state ----
    state > before
    rc=0
    bash "$restore" > restore.log 2>&1 || rc=$?
    state > after
    compare before after > delta

    [ "$rc" -eq 0 ] || fail "restore exited $rc"
    [ ! -e "$XDG_STATE_HOME/omarchy/preinstalls-removed" ] || fail "preinstalls-removed still present after Restore"
    cmp -s "$tree/applications/YouTube.desktop" "$A/YouTube.desktop" || fail "Restore did not bring back YouTube.desktop"
    changed=$(pick C delta | join)
    [ -z "$changed" ] || fail "Restore changed files it should not touch: $changed"
    odd=$(pick A delta | grep -v '^home/.local/share/applications/' | join || true)
    [ -z "$odd" ] || fail "Restore wrote unexpected files: $odd"
    [ ! -e "$real_home" ] || fail "wrote outside the fixture: $real_home"
    if [ "''${#fails[@]}" -gt 0 ]; then cat restore.log >&2; fi
    report
    echo "restore: added $(pick A delta | wc -l) launchers, changed nothing"

    touch $out
  ''
