{ pkgs, ... }:
# pkgs/writer-lock.sh, the helper every config writer takes apply's lock and
# its file-keeping write from (#1789). Each case sources the real file in a
# subshell, because nx_refuse exits. Every case runs and failures are counted.
pkgs.runCommand "nixarchy-writer-lock"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      gnused
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

    if [ "$fails" -ne 0 ]; then echo "$fails case(s) failed"; exit 1; fi
    touch $out
  ''
