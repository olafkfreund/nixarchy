{ inputs, pkgs }:
# pkgs/writer-lock.sh, the helper every config writer takes apply's lock and
# its file-keeping write from (#1789). Each case sources the real file in a
# subshell, because nx_refuse exits. Every case runs and failures are counted.
let
  testLib = import ./lib.nix { inherit inputs; };
  search = testLib.vmPackage "nixarchy-search";
  bin = name: "${testLib.vmPackage "nixarchy-${name}"}/bin/nixarchy-${name}";
in
pkgs.runCommand "nixarchy-writer-lock"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      gnused
      gnugrep
      gawk
      nix
      util-linux
    ];
  }
  ''
    set +e # stdenv runs with -e; cases read $? themselves
    fails=0
    pass() { echo "PASS  $1"; }
    fail() { echo "FAIL  $1: $2"; fails=$((fails + 1)); }

    export HOME=$TMPDIR/home
    export XDG_STATE_HOME=$TMPDIR/state
    mkdir -p "$HOME" "$XDG_STATE_HOME/nixarchy/applied"
    unset NIXARCHY_LOCK_HELD
    lib=${../pkgs/writer-lock.sh}
    lock=$XDG_STATE_HOME/nixarchy/applied/lock
    w=$TMPDIR/work
    mkdir -p "$w"

    # A holder of the lock, for the contention cases.
    ( exec 8>>"$lock"; flock 8; exec sleep 30 ) &
    holder=$!
    sleep 1

    # 1. Contention: nx_lock gives up after about five seconds, with the cause.
    start=$(date +%s)
    ( . "$lib"; nx_lock ) 2> "$w/err1"; rc=$?
    took=$(( $(date +%s) - start ))
    if [ "$rc" = 75 ] && [ "$took" -ge 5 ] && [ "$took" -le 7 ] && grep -q 'a write or an apply is running' "$w/err1"; then
      pass '1 contention'
    else
      fail '1 contention' "rc=$rc took=$took stderr=$(cat "$w/err1")"
    fi

    # 2. Nesting: the same holder, with the handshake set.
    start=$(date +%s)
    ( . "$lib"; NIXARCHY_LOCK_HELD=1 nx_lock ); rc=$?
    took=$(( $(date +%s) - start ))
    if [ "$rc" = 0 ] && [ "$took" -lt 1 ]; then pass '2 nesting'; else fail '2 nesting' "rc=$rc took=$took"; fi

    kill "$holder"; wait "$holder" 2>/dev/null || :

    # 3. Stale handshake: a non-owner's nx_unlock still clears it for children.
    seen=$( . "$lib"; export NIXARCHY_LOCK_HELD=1; nx_unlock; sh -c 'echo "''${NIXARCHY_LOCK_HELD-unset}"' )
    if [ "$seen" = unset ]; then pass '3 stale handshake'; else fail '3 stale handshake' "child saw NIXARCHY_LOCK_HELD=$seen"; fi

    # 4. Fail closed: a state directory that cannot be created.
    mkdir -p "$w/ro"; chmod 0500 "$w/ro"
    ( XDG_STATE_HOME=$w/ro; . "$lib"; nx_lock ) 2> "$w/err4"; rc=$?
    chmod 0700 "$w/ro"
    if [ "$rc" = 75 ] && grep -q 'cannot create' "$w/err4"; then pass '4 fail closed'; else fail '4 fail closed' "rc=$rc stderr=$(cat "$w/err4")"; fi

    # 5. Keeps the file: mode, inode and symlink survive a write through a link.
    printf '%s\n' old > "$w/t5"; chmod 640 "$w/t5"; ln -s t5 "$w/l5"
    printf '%s\n' new > "$w/s5"
    ino=$(stat -L -c %i "$w/l5")
    ( . "$lib"; nx_put "$w/s5" "$w/l5" ); rc=$?
    if [ "$rc" = 0 ] && [ -L "$w/l5" ] && [ "$(stat -L -c %i "$w/l5")" = "$ino" ] \
      && [ "$(stat -c %a "$w/t5")" = 640 ] && [ "$(cat "$w/t5")" = new ]; then
      pass '5 keeps the file'
    else
      fail '5 keeps the file' "rc=$rc link=$([ -L "$w/l5" ] && echo kept || echo lost) ino=$(stat -L -c %i "$w/l5" 2>&1)/$ino mode=$(stat -c %a "$w/l5" 2>&1) content=$(cat "$w/l5" 2>&1)"
    fi

    # 6. Read-only target: refused, and nothing about it changes.
    printf '%s\n' keep > "$w/t6"; chmod 444 "$w/t6"
    printf '%s\n' new > "$w/s6"
    ino=$(stat -c %i "$w/t6")
    ( . "$lib"; nx_put "$w/s6" "$w/t6" ) 2>/dev/null; rc=$?
    if [ "$rc" = 75 ] && [ "$(cat "$w/t6")" = keep ] && [ "$(stat -c %i "$w/t6")" = "$ino" ]; then
      pass '6 read-only target'
    else
      fail '6 read-only target' "rc=$rc content=$(cat "$w/t6") ino=$(stat -c %i "$w/t6")/$ino"
    fi

    # 7. Interrupted write: SIGINT to the group mid-copy leaves the whole new content.
    set -m
    trap "" PIPE # a broken write must read as a failed case, not kill the script
    mkfifo "$w/s7"
    printf '%s\n' old > "$w/t7"
    ( . "$lib"; nx_put "$w/s7" "$w/t7" ) &
    pgid=$!
    exec 7>"$w/s7"
    printf 'first-half;' >&7
    sleep 0.5
    kill -INT -- "-$pgid"
    printf 'second-half' >&7
    exec 7>&-
    wait "$pgid"; rc=$?
    set +m
    if [ -f "$w/t7" ]; then got7=$(cat "$w/t7"); else got7='(not a regular file)'; fi
    if [ "$rc" = 0 ] && [ "$got7" = 'first-half;second-half' ]; then
      pass '7 interrupted write'
    else
      fail '7 interrupted write' "rc=$rc content=$got7"
    fi

    # 8. Failed write, restored: a 1 KiB file limit lets the 500 B backup copy
    # through and stops the 2048 B write.
    head -c 500 /dev/zero | tr '\0' o > "$w/t8"
    head -c 2048 /dev/zero | tr '\0' n > "$w/s8"
    cp "$w/t8" "$w/t8.orig"
    ( ulimit -S -f 1; . "$lib"; nx_put "$w/s8" "$w/t8" ) 2>/dev/null; rc=$?
    if [ "$rc" = 75 ] && cmp -s "$w/t8" "$w/t8.orig"; then
      pass '8 failed write, restored'
    else
      fail '8 failed write, restored' "rc=$rc size=$(stat -c %s "$w/t8")"
    fi

    # 9. Commit refusal: the target moved on since the snapshot.
    printf '%s\n' A > "$w/snap9"; printf '%s\n' B > "$w/t9"; printf '%s\n' C > "$w/work9"
    ( . "$lib"; nx_commit "$w/snap9" "$w/work9" "$w/t9" test ) 2>/dev/null; rc=$?
    if [ "$rc" = 75 ] && [ "$(cat "$w/t9")" = B ]; then pass '9 commit refusal'; else fail '9 commit refusal' "rc=$rc content=$(cat "$w/t9")"; fi

    # 10-13. search's insert_line, taken from the built script. Parsing needs a
    # private nix state directory.
    export NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-state
    mkdir -p nix-state
    sed -n '/^insert_line() {/,/^}/p' ${search}/bin/nixarchy-search > "$w/insert_line.sh"
    [ -s "$w/insert_line.sh" ] || { echo "insert_line is not in nixarchy-search any more" >&2; exit 1; }
    mkins() { printf '%s\n' '{ ... }:' '{' "$@" '}' > "$w/apps.nix"; chmod 640 "$w/apps.nix"; }
    # Literal backslash-n, as add_option passes it: awk -v turns it into newlines.
    row='\n  a.b = 1;  #@opt a.b\n'
    ins() { ( . "$lib"; . "$w/insert_line.sh"; file=$1; insert_line "$2" "$3" ); }

    # 10. Refused while somebody holds the lock; the file is untouched.
    mkins
    cp "$w/apps.nix" "$w/apps.before"
    ( exec 8>>"$lock"; flock 8; exec sleep 30 ) &
    holder=$!
    sleep 1
    ins "$w/apps.nix" "$row" a.b 2>/dev/null; rc=$?
    kill "$holder"; wait "$holder" 2>/dev/null || :
    if [ "$rc" = 75 ] && cmp -s "$w/apps.nix" "$w/apps.before"; then pass '10 insert_line refused under a held lock'; else fail '10 insert_line refused under a held lock' "rc=$rc"; fi

    # 11. A duplicate marker is not written twice.
    mkins '  a.b = 1;  #@opt a.b'
    cp "$w/apps.nix" "$w/apps.before"
    ins "$w/apps.nix" "$row" a.b; rc=$?
    if [ "$rc" = 2 ] && cmp -s "$w/apps.nix" "$w/apps.before"; then pass '11 insert_line returns 2 on a duplicate'; else fail '11 insert_line returns 2 on a duplicate' "rc=$rc"; fi

    # 12. A symlinked target keeps its link and inode.
    mkins
    mv "$w/apps.nix" "$w/real-apps.nix"; ln -s real-apps.nix "$w/apps.nix"
    ino=$(stat -L -c %i "$w/apps.nix")
    ins "$w/apps.nix" "$row" a.b; rc=$?
    if [ "$rc" = 0 ] && [ -L "$w/apps.nix" ] && [ "$(stat -L -c %i "$w/apps.nix")" = "$ino" ] && grep -q '#@opt a.b$' "$w/real-apps.nix"; then
      pass '12 insert_line keeps a symlinked target'
    else
      fail '12 insert_line keeps a symlinked target' "rc=$rc ino=$(stat -L -c %i "$w/apps.nix")/$ino"
    fi
    rm -f "$w/apps.nix" "$w/real-apps.nix"

    # 13. A line that would not parse is refused with status 1, file untouched.
    mkins
    cp "$w/apps.nix" "$w/apps.before"
    ins "$w/apps.nix" '\n  a.b = ((;  #@opt a.b\n' a.b 2>/dev/null; rc=$?
    if [ "$rc" = 1 ] && cmp -s "$w/apps.nix" "$w/apps.before"; then pass '13 insert_line refuses an unparseable result'; else fail '13 insert_line refuses an unparseable result' "rc=$rc"; fi

    # The writer matrix: every writer, three ways. (a) refused with exit 75 and the
    # target untouched while somebody holds the lock; (b) succeeds under the
    # handshake with that holder still running; (c) keeps a symlinked target's
    # link and inode. Rows run one after another, each from a freshly written target.
    export XDG_CONFIG_HOME=$TMPDIR/config
    export NIXARCHY_TEMPLATES=$TMPDIR/templates
    cfg=$XDG_CONFIG_HOME/nixarchy
    real=$TMPDIR/real
    mkdir -p "$cfg" "$NIXARCHY_TEMPLATES" "$real"
    printf '%s\n' '{"da":{}}' > "$w/registry.json"
    export NIXARCHY_LANGUAGE_REGISTRY=$w/registry.json
    g_apps_off() { printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '    # firefox.enable = true;  #@ firefox' '  };' '}'; }
    g_apps_on() { printf '%s\n' '{ ... }: {' '  programs.nixarchy.apps = {' '    firefox.enable = true;  #@ firefox' '  };' '}'; }
    g_svc_none() { printf '%s\n' '{ ... }:' '{' '}'; }
    g_svc_off() { printf '%s\n' '{ ... }:' '{' '  # services.foo.enable = true;  #@ foo' '}'; }
    g_svc_on() { printf '%s\n' '{ ... }:' '{' '  services.foo.enable = true;  #@ foo' '}'; }
    g_pkg() { printf '%s\n' '{ pkgs, ... }:' '{' '  environment.systemPackages = with pkgs; [  #@pkgs-begin' '    ripgrep  #@pkg ripgrep' '  ];  #@pkgs-end' '}'; }
    g_draft() { printf '%s\n' '{ pkgs, ... }:' '{' '  environment.systemPackages = [' '    # (callPackage ./packages/tool.nix { })  #@draft tool' '  ];' '}'; }
    g_opt() { printf '%s\n' '{ ... }:' '{' "" '  a.b = 1;  #@opt a.b' '}'; }
    g_bare() { printf '%s\n' '{ pkgs, ... }:' '{' '}'; }
    g_apps_off > "$NIXARCHY_TEMPLATES/apps-template.nix"
    g_svc_off > "$NIXARCHY_TEMPLATES/services-template.nix"

    hold() { ( exec 8>>"$lock"; flock 8; exec sleep 30 ) & holder=$!; sleep 0.5; }
    unhold() { kill "$holder"; wait "$holder" 2>/dev/null; }

    # row NAME FILE GENERATOR COMMAND...
    row() {
      local name=$1 base=$2 gen=$3 t r rc ino
      shift 3
      t=$cfg/$base
      r=$real/$base
      rm -f "$t" "$r"

      "$gen" > "$t"; chmod 640 "$t"; cp "$t" "$w/m.before"; ino=$(stat -c %i "$t")
      hold; "$@" > "$w/m.out" 2>&1; rc=$?; unhold
      if [ "$rc" = 75 ] && cmp -s "$t" "$w/m.before" && [ "$(stat -c %i "$t")" = "$ino" ]; then
        pass "$name (a) refused under a held lock"
      else
        fail "$name (a) refused under a held lock" "rc=$rc same=$(cmp -s "$t" "$w/m.before" && echo yes || echo no) out=$(tail -3 "$w/m.out")"
      fi

      rm -f "$t"; "$gen" > "$t"
      hold; NIXARCHY_LOCK_HELD=1 "$@" > "$w/m.out" 2>&1; rc=$?; unhold
      if [ "$rc" = 0 ] && ! cmp -s "$t" "$w/m.before"; then
        pass "$name (b) succeeds under the handshake"
      else
        fail "$name (b) succeeds under the handshake" "rc=$rc out=$(tail -3 "$w/m.out")"
      fi

      rm -f "$t"; "$gen" > "$r"; chmod 640 "$r"; ln -s "$r" "$t"; ino=$(stat -c %i "$r")
      "$@" > "$w/m.out" 2>&1; rc=$?
      if [ "$rc" = 0 ] && [ -L "$t" ] && [ "$(stat -c %i "$r")" = "$ino" ] && ! cmp -s "$r" "$w/m.before"; then
        pass "$name (c) keeps a symlinked target"
      else
        fail "$name (c) keeps a symlinked target" "rc=$rc link=$([ -L "$t" ] && echo kept || echo lost) ino=$(stat -c %i "$r")/$ino out=$(tail -3 "$w/m.out")"
      fi
    }

    row catalogue-diff services.nix g_svc_none ${bin "catalogue-diff"} --add-one services foo
    row service-enable services.nix g_svc_off ${bin "service-enable"} foo
    row service-disable services.nix g_svc_on ${bin "service-disable"} foo
    row language-select services.nix g_svc_none ${bin "language-select"} da
    row app-enable apps.nix g_apps_off ${bin "app-enable"} firefox
    row app-disable apps.nix g_apps_on ${bin "app-disable"} firefox
    row pkg-remove apps.nix g_pkg ${bin "pkg-remove"} ripgrep
    row pkg-undraft apps.nix g_draft ${bin "pkg-undraft"} tool
    row opt-remove apps.nix g_opt ${bin "opt-remove"} a.b
    row pkg-add apps.nix g_bare ${bin "pkg-add"} kdePackages.kdenlive

    if [ "$fails" -ne 0 ]; then echo "$fails case(s) failed"; exit 1; fi
    touch $out
  ''
