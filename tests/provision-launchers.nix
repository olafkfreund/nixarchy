{ pkgs, ... }:
# First login adds only missing launchers and stubs; it replaces nothing (#1319).
#
# Two paths wrote over a user's files: install/user/mise.sh (all.sh:14), and
# omarchy-provision-user:126 -> omarchy-refresh-applications, which cp -f'd the
# launchers and ran mise.sh again. A copy at the store's 444 once left files the
# next run could not rewrite, which aborted provisioning under set -euo pipefail
# before finalize-user was marked. The fix is to skip existing files, and this
# check runs both calls twice. See tests/AGENTS.md#provision-launchers-runs-two-calls-not-provisioning.
let
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-provision-launchers"
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
    refresh = "${shipped}/share/omarchy/bin/omarchy-refresh-applications";
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

    # Stubs: record the call and succeed. alacritty makes omarchy-cmd-present
    # true, so the Alacritty.desktop branch runs.
    mkdir -p "$TMPDIR/stubs"
    for n in mise update-desktop-database omarchy-install-hermes-cli alacritty; do
      printf '#!%s\necho "%s $*" >> "$TMPDIR/calls"\nexit 0\n' "$shell" "$n" > "$TMPDIR/stubs/$n"
    done
    chmod +x "$TMPDIR"/stubs/*
    export PATH=$TMPDIR/stubs:$tree/bin:$PATH

    # Fixture. Read-only, differing Home Manager targets: cp -f writes through a
    # link whose target is writable, so a writable twin could not go red.
    sed 's|https://launchpad.37signals.com|https://example.org/bc|' "$tree/applications/Basecamp.desktop" > "$A/Basecamp.desktop"
    sed 's|^Name=.*|Name=Zoom (mine)|' "$tree/applications/Zoom.desktop" > "$HM/Zoom.desktop"
    chmod 444 "$HM/Zoom.desktop"
    ln -s "$HM/Zoom.desktop" "$A/Zoom.desktop"
    cp --no-preserve=mode "$tree/applications/YouTube.desktop" "$A/YouTube.desktop"
    chmod 444 "$A/YouTube.desktop"
    printf '#!/bin/bash\nexec /opt/claude "$@"\n' > "$HM/claude"
    chmod 555 "$HM/claude"
    ln -s "$HM/claude" "$B/claude"

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

    # First login's two writers, in provision-user's order; $1 labels the logs.
    provision() {
      local rc=0 line
      bash -eE -c 'source "$1"' bash "$tree/install/user/mise.sh" > "$1-mise.log" 2>&1 || rc=$?
      [ "$rc" -eq 0 ] || fail "mise.sh exited $rc ($1)"
      rc=0
      bash "$refresh" > "$1-refresh.log" 2>&1 || rc=$?
      [ "$rc" -eq 0 ] || fail "refresh exited $rc ($1)"
      # The script has no set -e and ends in an if, so its status hides a failed cp.
      line=$(grep -E 'cp:|Permission denied' "$1-refresh.log" | head -n1 || true)
      [ -z "$line" ] || fail "refresh printed a copy error ($1): $line"
    }

    # ---- Dirty home, first run ----
    state > before
    provision first
    state > after
    compare before after > delta

    [ -z "$(pick D delta)" ] || fail "deleted files: $(pick D delta | join)"
    pick C delta | grep 'Basecamp.desktop$' >/dev/null && fail "Basecamp.desktop changed"
    changed=$(pick C delta | join)
    [ -z "$changed" ] || fail "changed files it should not touch: $changed"
    [ "$(readlink "$A/Zoom.desktop" || true)" = "$HM/Zoom.desktop" ] || fail "Zoom.desktop is no longer a link"
    [ "$(readlink "$B/claude" || true)" = "$HM/claude" ] || fail ".local/bin/claude is no longer a link"

    want=$(
      {
        for f in "$tree"/applications/*.desktop; do
          n=''${f##*/}
          case $n in
            Basecamp.desktop | Zoom.desktop | YouTube.desktop) ;;
            *) printf 'home/.local/share/applications/%s\n' "$n" ;;
          esac
        done
        printf 'home/.local/share/applications/Alacritty.desktop\n'
      } | sort
    )
    got=$(pick A delta)
    missing=$(comm -13 <(printf '%s\n' "$got") <(printf '%s\n' "$want") | join)
    extra=$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got") | join)
    [ -z "$missing" ] || fail "not seeded: $missing"
    [ -z "$extra" ] || fail "wrote unexpected files: $extra"

    grep -qx 'mise reshim --system' "$TMPDIR/calls" || fail "mise.sh did not reshim"
    for f in "$tree"/applications/*.desktop; do
      n=''${f##*/}
      case $n in Basecamp.desktop | Zoom.desktop | YouTube.desktop) continue ;; esac
      cmp -s "$f" "$A/$n" || fail "$n differs from its source"
    done
    cmp -s "$tree/default/alacritty/Alacritty.desktop" "$A/Alacritty.desktop" || fail "Alacritty.desktop differs from its source"

    # ---- Second run: must change nothing ----
    state > before
    provision second
    state > after
    compare before after > delta
    again=$(sed 's/\t/ /' delta | join)
    [ -z "$again" ] || fail "second run changed: $again"

    # ---- Clean home ----
    export HOME=$TMPDIR/clean
    export XDG_DATA_HOME=$HOME/.local/share
    export XDG_STATE_HOME=$HOME/.local/state
    export XDG_CONFIG_HOME=$HOME/.config
    export XDG_CACHE_HOME=$HOME/.cache
    A=$HOME/.local/share/applications
    mkdir -p "$HOME"
    provision clean
    for f in "$tree"/applications/*.desktop "$tree/default/alacritty/Alacritty.desktop"; do
      n=''${f##*/}
      cmp -s "$f" "$A/$n" || fail "clean home missing $n"
    done

    [ ! -e "$real_home" ] || fail "wrote outside the fixture: $real_home"
    for l in first-refresh.log second-refresh.log clean-refresh.log first-mise.log; do
      if [ "''${#fails[@]}" -gt 0 ]; then echo "--- $l" >&2; cat "$l" >&2; fi
    done
    report
    echo "provision: dirty home untouched, $(printf '%s\n' "$want" | wc -l) seeded, second run changed nothing"

    touch $out
  ''
