{ pkgs, script }:
pkgs.runCommand "nixarchy-home-backup-restore"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.findutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    fail() { echo "FAIL: $1" >&2; exit 1; }
    setup() {
      home=$TMPDIR/$1/home
      repo=$TMPDIR/$1/repo
      flake=$TMPDIR/$1/flake
      log=$TMPDIR/$1/log
      mkdir -p "$home" "$repo/.git" "$flake"
      touch "$flake/.nixarchy-url"
    }
    restore() {
      HOME=$home NIXARCHY_HOME_BACKUP_REPO=$repo NIXARCHY_FLAKE=$flake \
        bash ${script} restore "$@" > "$log" 2>&1
    }
    red() {
      if restore "$@"; then fail "$case_name: restore unexpectedly succeeded"; fi
      if grep -q 'Done\.' "$log"; then fail "$case_name: failed restore said Done"; fi
    }

    case_name=allowlist
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy" "$repo/.local/state/omarchy" "$repo/.notes" "$repo/.ssh" "$repo/.config/hypr" "$home/.config/omarchy" "$home/.config/hypr"
    printf 'shell\n' > "$repo/.config/omarchy/shell.json"
    printf '.ssh/\n.notes/custom.txt\n' > "$repo/.config/omarchy/backup.list"
    printf '# local only\n.config/omarchy/\n' > "$home/.config/omarchy/backup.list"
    cp "$home/.config/omarchy/backup.list" "$TMPDIR/local-list-original"
    printf 'custom\n' > "$repo/.notes/custom.txt"
    printf 'secret\n' > "$repo/.ssh/authorized_keys"
    printf 'clipboard\n' > "$repo/.local/state/omarchy/clipboard-history.json"
    printf 'hook\n' > "$repo/.config/hypr/hook.sh"
    chmod +x "$repo/.config/hypr/hook.sh"
    printf 'old hook\n' > "$home/.config/hypr/hook.sh"
    chmod -x "$home/.config/hypr/hook.sh"
    restore || fail "first restore failed: $(cat "$log")"
    test -f "$home/.config/omarchy/shell.json" || fail "shipped file missing"
    test -x "$home/.config/hypr/hook.sh" || fail "executable mode lost"
    test ! -e "$home/.notes/custom.txt" || fail "repo backup.list authorized a custom file"
    test ! -e "$home/.ssh/authorized_keys" || fail "extra repo file restored"
    test ! -e "$home/.local/state/omarchy/clipboard-history.json" || fail "excluded clipboard restored"
    cmp -s "$TMPDIR/local-list-original" "$home/.config/omarchy/backup.list" || fail "restore changed the local allowlist"
    grep -qF '2 restored, 0 already matched, 1 of yours saved' "$log" || fail "first-run counts were wrong"
    grep -qF '.ssh/' "$log" || fail "repo-only path was not named"
    grep -qF 'Add wanted paths to ~/.config/omarchy/backup.list' "$log" || fail "local opt-in instruction missing"
    restore || fail "second restore failed: $(cat "$log")"
    grep -qF '0 restored, 2 already matched, 0 of yours saved' "$log" || fail "matched counts were wrong"
    test ! -e "$home/.notes/custom.txt" || fail "repo list authorized custom file on rerun"
    test ! -e "$home/.ssh/authorized_keys" || fail "extra repo file restored on rerun"
    printf '.notes/custom.txt\n' >> "$home/.config/omarchy/backup.list"
    restore || fail "local opt-in restore failed: $(cat "$log")"
    test -f "$home/.notes/custom.txt" || fail "local custom entry was not restored"

    case_name=destination-symlink
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy" "$home/.config/omarchy"
    printf 'replacement\n' > "$repo/.config/omarchy/shell.json"
    printf 'original\n' > "$TMPDIR/outside-file"
    ln -s "$TMPDIR/outside-file" "$home/.config/omarchy/shell.json"
    red --force
    grep -q 'Refusing symlink' "$log" || fail "destination symlink lacked a diagnosis: $(cat "$log")"
    grep -qx original "$TMPDIR/outside-file" || fail "destination symlink target changed"

    case_name=parent-symlink
    setup "$case_name"
    mkdir -p "$repo/.config/hypr" "$home/.config" "$TMPDIR/outside-dir"
    printf 'replacement\n' > "$repo/.config/hypr/hyprland.lua"
    ln -s "$TMPDIR/outside-dir" "$home/.config/hypr"
    red
    grep -q 'Refusing symlinked directory' "$log" || fail "parent symlink lacked a diagnosis"
    test ! -e "$TMPDIR/outside-dir/hyprland.lua" || fail "parent symlink target changed"

    case_name=repo-symlink
    setup "$case_name"
    mkdir -p "$repo/.config" "$TMPDIR/repo-outside"
    printf 'outside\n' > "$TMPDIR/repo-outside/hyprland.lua"
    ln -s "$TMPDIR/repo-outside" "$repo/.config/hypr"
    red
    grep -q 'Refusing symlinked backup path' "$log" || fail "repo symlink lacked a diagnosis"
    test ! -e "$home/.config/hypr/hyprland.lua" || fail "repo symlink was traversed"

    case_name=newline-name
    setup "$case_name"
    mkdir -p "$repo/.config/hypr"
    printf 'bad\n' > "$repo/.config/hypr/"$'bad\nname'
    red
    grep -q 'Unsafe backup path' "$log" || fail "newline filename was not diagnosed"

    case_name=unsafe-entry
    setup "$case_name"
    mkdir -p "$home/.config/omarchy"
    printf '../outside\n' > "$home/.config/omarchy/backup.list"
    red
    grep -q 'Unsafe path in your local backup.list' "$log" || fail "parent traversal was not diagnosed"
    printf '/etc/passwd\n' > "$home/.config/omarchy/backup.list"
    red
    grep -q 'Unsafe path in your local backup.list' "$log" || fail "absolute entry was not diagnosed"
    printf './.config/omarchy/\n' > "$home/.config/omarchy/backup.list"
    red
    grep -q 'Unsafe path in your local backup.list' "$log" || fail "alias of the local list was not diagnosed"

    case_name=trailing-home
    setup "$case_name"
    mkdir -p "$repo/.config/hypr"
    printf 'safe\n' > "$repo/.config/hypr/hyprland.lua"
    HOME=$home/ NIXARCHY_HOME_BACKUP_REPO=$repo NIXARCHY_FLAKE=$flake \
      bash ${script} restore > "$log" 2>&1 || fail "trailing HOME slash failed: $(cat "$log")"
    test -f "$home/.config/hypr/hyprland.lua" || fail "trailing HOME slash lost the destination"

    case_name=find-failure
    setup "$case_name"
    mkdir -p "$repo/.config/hypr" "$TMPDIR/stubs"
    printf 'sample\n' > "$repo/.config/hypr/hyprland.lua"
    printf '#!%s\nexit 42\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/find"
    chmod +x "$TMPDIR/stubs/find"
    old_path=$PATH
    export PATH=$TMPDIR/stubs:$PATH
    red
    export PATH=$old_path
    grep -q 'Could not walk the backup allowlist' "$log" || fail "find error was masked"
    rm "$TMPDIR/stubs/find"

    case_name=save-failure
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy" "$home/.config/omarchy" "$TMPDIR/stubs"
    printf 'replacement\n' > "$repo/.config/omarchy/shell.json"
    printf 'original\n' > "$home/.config/omarchy/shell.json"
    printf '#!%s\necho 123\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/date"
    chmod +x "$TMPDIR/stubs/date"
    printf 'occupied\n' > "$home/.config/omarchy/shell.json.bak.123"
    export PATH=$TMPDIR/stubs:$PATH
    red
    export PATH=$old_path
    grep -q 'Could not save your existing' "$log" || fail "failed save lacked a diagnosis"
    grep -qx original "$home/.config/omarchy/shell.json" || fail "failed save overwrote existing file"

    case_name=copy-failure
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy"
    printf 'replacement\n' > "$repo/.config/omarchy/shell.json"
    printf '#!%s\nexit 23\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/cp"
    chmod +x "$TMPDIR/stubs/cp"
    export PATH=$TMPDIR/stubs:$PATH
    red
    export PATH=$old_path
    grep -q 'Could not restore' "$log" || fail "failed copy lacked a diagnosis"
    test ! -e "$home/.config/omarchy/shell.json" || fail "failed copy left an unexpected destination"

    echo "home backup restore limits paths and reports failed copies (#1080)"
    touch "$out"
  ''
