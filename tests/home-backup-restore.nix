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
    mkdir -p "$repo/.config/omarchy" "$repo/.local/state/omarchy" "$repo/.notes" "$repo/.ssh" "$repo/.config/hypr"
    printf 'shell\n' > "$repo/.config/omarchy/shell.json"
    printf '.notes/custom.txt\n' > "$repo/.config/omarchy/backup.list"
    printf 'custom\n' > "$repo/.notes/custom.txt"
    printf 'secret\n' > "$repo/.ssh/authorized_keys"
    printf 'clipboard\n' > "$repo/.local/state/omarchy/clipboard-history.json"
    printf 'hook\n' > "$repo/.config/hypr/hook.sh"
    chmod +x "$repo/.config/hypr/hook.sh"
    restore || fail "first restore failed: $(cat "$log")"
    test -f "$home/.config/omarchy/shell.json" || fail "shipped file missing"
    test -x "$home/.config/hypr/hook.sh" || fail "executable mode lost"
    test ! -e "$home/.notes/custom.txt" || fail "repo backup.list authorized a first-run custom file"
    test ! -e "$home/.ssh/authorized_keys" || fail "extra repo file restored"
    test ! -e "$home/.local/state/omarchy/clipboard-history.json" || fail "excluded clipboard restored"
    grep -q 'Rerun.*backup restore' "$log" || fail "missing second-run instruction"
    restore || fail "second restore failed: $(cat "$log")"
    test -f "$home/.notes/custom.txt" || fail "local custom entry was not restored on rerun"
    test ! -e "$home/.ssh/authorized_keys" || fail "extra repo file restored on rerun"

    case_name=destination-symlink
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy" "$home/.config/omarchy"
    printf 'replacement\n' > "$repo/.config/omarchy/shell.json"
    printf 'original\n' > "$TMPDIR/outside-file"
    ln -s "$TMPDIR/outside-file" "$home/.config/omarchy/shell.json"
    red --force
    grep -q 'Refusing symlink' "$log" || fail "destination symlink lacked a diagnosis"
    grep -qx original "$TMPDIR/outside-file" || fail "destination symlink target changed"

    case_name=parent-symlink
    setup "$case_name"
    mkdir -p "$repo/.config/hypr" "$home/.config" "$TMPDIR/outside-dir"
    printf 'replacement\n' > "$repo/.config/hypr/hyprland.lua"
    ln -s "$TMPDIR/outside-dir" "$home/.config/hypr"
    red
    grep -q 'Refusing symlinked directory' "$log" || fail "parent symlink lacked a diagnosis"
    test ! -e "$TMPDIR/outside-dir/hyprland.lua" || fail "parent symlink target changed"

    case_name=save-failure
    setup "$case_name"
    mkdir -p "$repo/.config/omarchy" "$home/.config/omarchy" "$TMPDIR/stubs"
    printf 'replacement\n' > "$repo/.config/omarchy/shell.json"
    printf 'original\n' > "$home/.config/omarchy/shell.json"
    printf '#!%s\necho 123\n' ${pkgs.bash}/bin/bash > "$TMPDIR/stubs/date"
    chmod +x "$TMPDIR/stubs/date"
    printf 'occupied\n' > "$home/.config/omarchy/shell.json.bak.123"
    old_path=$PATH
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
    test ! -e "$home/.config/omarchy/shell.json" || fail "failed copy counted as restored"

    echo "home backup restore limits paths and reports failed copies (#1080)"
    touch "$out"
  ''
