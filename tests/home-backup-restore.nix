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
    printf 'theme\n' > "$repo/.local/state/omarchy/theme.name"
    printf '.ssh/\n.notes/custom.txt\n' > "$repo/.config/omarchy/backup.list"
    printf 'evil\033]52;c;AAAA\a\n' >> "$repo/.config/omarchy/backup.list"
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
    test -f "$home/.local/state/omarchy/theme.name" || fail "shipped file missing"
    test -x "$home/.config/hypr/hook.sh" || fail "executable mode lost"
    test ! -e "$home/.notes/custom.txt" || fail "repo backup.list authorized a custom file"
    test ! -e "$home/.ssh/authorized_keys" || fail "extra repo file restored"
    test ! -e "$home/.local/state/omarchy/clipboard-history.json" || fail "excluded clipboard restored"
    cmp -s "$TMPDIR/local-list-original" "$home/.config/omarchy/backup.list" || fail "restore changed the local allowlist"
    grep -qF '2 restored, 0 already matched, 1 of yours saved' "$log" || fail "first-run counts were wrong"
    grep -qF '.ssh/' "$log" || fail "repo-only path was not named"
    hostile_line=$(grep -F 'evil' "$log") || fail "hostile repo-only path was not named"
    [[ $hostile_line != *$'\033'* ]] || fail "repo-only path printed an ESC byte"
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
    mkdir -p "$repo/.local/state/omarchy" "$home/.local/state/omarchy"
    printf 'replacement\n' > "$repo/.local/state/omarchy/theme.name"
    printf 'original\n' > "$TMPDIR/outside-file"
    ln -s "$TMPDIR/outside-file" "$home/.local/state/omarchy/theme.name"
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
    mkdir -p "$repo/.local/state/omarchy" "$home/.local/state/omarchy" "$TMPDIR/stubs"
    printf 'replacement\n' > "$repo/.local/state/omarchy/theme.name"
    printf 'original\n' > "$home/.local/state/omarchy/theme.name"
    printf '#!%s\necho 123\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/date"
    chmod +x "$TMPDIR/stubs/date"
    printf 'occupied\n' > "$home/.local/state/omarchy/theme.name.bak.123"
    export PATH=$TMPDIR/stubs:$PATH
    red
    export PATH=$old_path
    grep -q 'Could not save your existing' "$log" || fail "failed save lacked a diagnosis"
    grep -qx original "$home/.local/state/omarchy/theme.name" || fail "failed save overwrote existing file"

    case_name=copy-failure
    setup "$case_name"
    mkdir -p "$repo/.local/state/omarchy"
    printf 'replacement\n' > "$repo/.local/state/omarchy/theme.name"
    printf '#!%s\nexit 23\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/cp"
    chmod +x "$TMPDIR/stubs/cp"
    export PATH=$TMPDIR/stubs:$PATH
    red
    export PATH=$old_path
    grep -q 'Could not restore' "$log" || fail "failed copy lacked a diagnosis"
    test ! -e "$home/.local/state/omarchy/theme.name" || fail "failed copy left an unexpected destination"

    mkdir -p "$TMPDIR/gumbin"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[[ $1 == choose ]] && { echo "Nowhere for now"; exit 0; }' \
      '[[ $* != *anyway* ]]' > "$TMPDIR/gumbin/gum"
    chmod +x "$TMPDIR/gumbin/gum"
    export PATH=$TMPDIR/gumbin:$PATH
    bsetup() {
      home=$TMPDIR/$1/home
      repo=$TMPDIR/$1/repo
      flake=$TMPDIR/$1/flake
      log=$TMPDIR/$1/log
      mkdir -p "$home/.config/omarchy" "$flake"
      touch "$flake/.nixarchy-url"
      printf '{}\n' > "$home/.config/omarchy/shell.json"
      HOME=$home git config --global user.name tester
      HOME=$home git config --global user.email tester@example.invalid
    }
    backup() {
      HOME=$home NIXARCHY_HOME_BACKUP_REPO=$repo NIXARCHY_FLAKE=$flake \
        bash ${script} backup > "$log" 2>&1
    }

    case_name=backup-foreign-dir
    bsetup "$case_name"
    mkdir -p "$repo"
    printf 'precious\n' > "$repo/keep.txt"
    cp "$repo/keep.txt" "$TMPDIR/keep-original"
    if backup; then fail "$case_name: backup into a foreign directory succeeded"; fi
    cmp -s "$TMPDIR/keep-original" "$repo/keep.txt" || fail "$case_name: foreign file was touched: $(cat "$log")"
    test ! -e "$repo/.git" || fail "$case_name: .git was created in a foreign directory"
    grep -q 'refusing to empty it' "$log" || fail "$case_name: no refusal in: $(cat "$log")"

    case_name=backup-foreign-git
    bsetup "$case_name"
    mkdir -p "$repo"
    HOME=$home git init -q -b main "$repo"
    printf 'tracked\n' > "$repo/a.txt"
    HOME=$home git -C "$repo" add a.txt
    HOME=$home git -C "$repo" commit -qm first
    printf 'unsaved work\n' > "$repo/wip.txt"
    if backup; then fail "$case_name: backup into a foreign repository succeeded"; fi
    grep -qx 'unsaved work' "$repo/wip.txt" || fail "$case_name: uncommitted file was deleted: $(cat "$log")"
    grep -q 'nixarchy-home-backup' "$log" || fail "$case_name: no adopt command in: $(cat "$log")"

    case_name=backup-default-upgrade
    bsetup "$case_name"
    repo=$home/.local/share/nixarchy/home-backup
    mkdir -p "$repo"
    HOME=$home git init -q -b main "$repo"
    printf 'old\n' > "$repo/old.txt"
    HOME=$home git -C "$repo" add old.txt
    HOME=$home git -C "$repo" commit -qm first
    HOME=$home NIXARCHY_FLAKE=$flake bash ${script} backup > "$log" 2>&1 \
      || fail "$case_name: upgrade of an unmarked default repository failed: $(cat "$log")"
    test -e "$repo/.git/nixarchy-home-backup" || fail "$case_name: marker missing"
    HOME=$home git -C "$repo" ls-files | grep -qx '.config/omarchy/shell.json' || fail "$case_name: shell.json not committed"

    case_name=backup-fresh
    bsetup "$case_name"
    backup || fail "$case_name: fresh backup failed: $(cat "$log")"
    test -e "$repo/.git/nixarchy-home-backup" || fail "$case_name: marker missing"
    HOME=$home git -C "$repo" ls-files | grep -qx '.config/omarchy/shell.json' || fail "$case_name: shell.json not committed"

    case_name=backup-link-out
    bsetup "$case_name"
    mkdir -p "$home/.aws" "$home/.config/hypr"
    printf 'aws-credential-body-xyz\n' > "$home/.aws/credentials"
    ln -s "$home/.aws/credentials" "$home/.config/hypr/hyprland.conf"
    backup || fail "$case_name: declining the review should still exit 0: $(cat "$log")"
    if HOME=$home git -C "$repo" rev-parse HEAD >/dev/null 2>&1; then fail "$case_name: a link out of the list was committed: $(cat "$log")"; fi
    if grep -rq --exclude-dir=.git aws-credential-body-xyz "$repo"; then fail "$case_name: the linked credential was copied into the repository"; fi
    grep -q 'hyprland.conf.*outside the backup list' "$log" || fail "$case_name: the link was not put to the credential review: $(cat "$log")"

    case_name=backup-link-store
    bsetup "$case_name"
    mkdir -p "$home/.config/hypr"
    ln -s ${pkgs.bash}/bin/bash "$home/.config/hypr/hyprland.conf"
    backup || fail "$case_name: backup failed: $(cat "$log")"
    if grep -q 'outside the backup list' "$log"; then fail "$case_name: a link into the store was flagged: $(cat "$log")"; fi
    test -f "$repo/.config/hypr/hyprland.conf" || fail "$case_name: the linked file was not copied"

    echo "home backup restore limits paths and reports failed copies (#1080)"
    touch "$out"
  ''
