{ inputs, pkgs }:
# What Home Manager activation and the default-plugins hook write, and when
# (#1276). Each is the module's own generated text, taken from the vm's
# evaluated home and run here with `run` behaving as Home Manager's does:
#
# - a merged JSON file keeps its mode, and the temp file lands beside it, so
#   the move is a rename rather than a copy out of /tmp;
# - a dry run writes nothing of ours: not the agent file's temp, not the
#   plugin reconcile's staging file;
# - an unreadable plugin list stops the post-boot hook rather than reading as
#   "nothing enabled" and turning plugins on past their rivals.
#
# The home is /home/omarchy in the vm, rewritten to the build directory, the
# way tests/options.nix's `au` runs the auto-update script.
let
  vm = inputs.self.nixosConfigurations.vm.extendModules {
    modules = [ { programs.nixarchy.defaultAgent = "opencode"; } ];
  };
  home = vm.config.home-manager.users.omarchy;
  act = name: pkgs.writeText "${name}.sh" home.home.activation.${name}.data;
  # #1705: the fallback needs a default that is not the hard-coded last resort.
  vmTheme = vm.extendModules {
    modules = [ { home-manager.users.omarchy.programs.nixarchy.defaultTheme = "gruvbox"; } ];
  };
  seedTheme = pkgs.writeText "seed-theme.sh" vmTheme.config.home-manager.users.omarchy.home.activation.nixarchySeed.data;
  themeHook =
    pkgs.writeText "theme-fallback"
      home.xdg.configFile."omarchy/hooks/post-boot.d/theme-fallback".text;
  hook =
    pkgs.writeText "default-plugins"
      home.xdg.configFile."omarchy/hooks/post-boot.d/default-plugins".text;
  # The one system activation step here: it writes a git config include.
  safeDir = pkgs.writeText "safe-dir.sh" vm.config.system.activationScripts.nixarchyFlakeSafeDirectory;
in
pkgs.runCommand "nixarchy-home-activation-writes"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.gawk
      pkgs.git
    ];
  }
  ''
    fails=0
    ok() { echo "  ok      $1"; }
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    root=$PWD
    mkdir -p tmp home/.config home/.local/state
    export TMPDIR=$root/tmp HOME=$root/home XDG_CONFIG_HOME=$root/home/.config XDG_STATE_HOME=$root/home/.local/state
    run() { if [[ -v DRY_RUN ]]; then echo "$@"; else "$@"; fi; }
    rehome() { sed "s|/home/omarchy|$root/home|g" "$1"; }

    # ---- a merged JSON file keeps its mode, and nothing is left in /tmp ----
    rehome ${act "nixarchyMcpClaude"} > mcp.sh
    conf=$(grep -o "conf=\"[^\"]*\"" mcp.sh | head -1 | cut -d'"' -f2)
    [ -n "$conf" ] || { echo "nixarchyMcpClaude names no file" >&2; exit 1; }
    mkdir -p "$(dirname "$conf")"
    echo '{"mine": true}' > "$conf"
    chmod 0644 "$conf"
    ( . ./mcp.sh ) > mcp.out 2>&1 || bad "the MCP merge failed: $(cat mcp.out)"
    [ "$(stat -c %a "$conf")" = 644 ] && ok "a merged JSON file keeps its mode" ||
      bad "a merged JSON file came back mode $(stat -c %a "$conf")"
    jq -e '.mine == true' "$conf" > /dev/null && ok "the merge keeps the user's keys" ||
      bad "the merge lost the user's keys: $(cat "$conf")"
    [ -z "$(ls -A tmp)" ] && ok "the merge leaves nothing in TMPDIR" ||
      bad "the merge left $(ls -A tmp) in TMPDIR"

    # ---- a dry run writes no agent file and no temp ----
    rehome ${act "nixarchyDefaultAgent"} > agent.sh
    ( DRY_RUN=1; . ./agent.sh ) > agent.out 2>&1 || bad "the agent step failed dry: $(cat agent.out)"
    [ -z "$(ls -A tmp)" ] && ok "a dry run leaves no agent temp file" ||
      bad "a dry run left $(ls -A tmp) in TMPDIR"
    [ ! -e home/.config/omarchy/defaults/agent ] && ok "a dry run writes no agent file" ||
      bad "a dry run wrote the agent file"
    ( . ./agent.sh ) > agent.out 2>&1 || bad "the agent step failed: $(cat agent.out)"
    [ "$(cat home/.config/omarchy/defaults/agent 2>/dev/null)" = opencode ] && ok "a real run writes the agent" ||
      bad "a real run wrote: $(cat home/.config/omarchy/defaults/agent 2>/dev/null)"

    # ---- a dry plugin reconcile writes no staging file ----
    # The block from its first comment to the manifest move's `fi`, plus the
    # dry-run cleanup line when there is one.
    rehome ${act "nixarchySeed"} > seed.sh
    awk '
      /Reconcile, never relink/ { on = 1 }
      on && done && /DRY_RUN/ { print; exit }
      on && done { exit }
      on { print }
      on && /run mv / { mv = 1 }
      on && mv && /^[[:space:]]*fi$/ { done = 1 }
    ' seed.sh > reconcile.sh
    grep -q 'run mv ' reconcile.sh || { echo "the plugin reconcile is not in nixarchySeed any more" >&2; exit 1; }
    mkdir -p home/.config/omarchy/plugins
    ( DRY_RUN=1; . ./reconcile.sh ) > reconcile.out 2>&1 || bad "the dry reconcile failed: $(cat reconcile.out)"
    [ ! -e home/.config/omarchy/.nixarchy-managed.new ] && [ -z "$(ls -A tmp)" ] &&
      ok "a dry plugin reconcile writes no staging file" ||
      bad "a dry plugin reconcile left $(ls -A home/.config/omarchy tmp | tr '\n' ' ')"

    # ---- #1342: the mimeapps hold ----
    # The activation seeds config/ at a switch, and a still-running 4.0.4
    # session that finds hyprland-mimeapps.list then recurses; the hold removes
    # a list this run created, leaving it to the login hook. The block runs
    # under `set -eu` as activation does (runCommand's shell does not, so only
    # this sees an unset variable). seed_dir is a stub that copies one list.
    awk '
      /#1342: hold the mimeapps list/ { on = 1 }
      on { print }
      on && /run rm -f/ { rm = 1 }
      on && rm && /^[[:space:]]*fi$/ { exit }
    ' seed.sh > hold.sh
    grep -q 'run rm -f' hold.sh || { echo "the mimeapps hold is not in nixarchySeed any more" >&2; exit 1; }
    list=home/.config/hyprland-mimeapps.list
    printf '%s\n' 'seeded' > fixture-list
    seed_dir() { [ -e "$2/hyprland-mimeapps.list" ] || [ -L "$2/hyprland-mimeapps.list" ] || run cp fixture-list "$2/hyprland-mimeapps.list"; }
    hold() { ( set -eu; . ./hold.sh ) > hold.out 2>&1 || bad "the hold failed: $(cat hold.out)"; }

    rm -f $list
    hold
    [ ! -e $list ] && grep -q 'seeded at your next login (#1342)' hold.out &&
      ok "a list this run created is removed, and the message is printed" ||
      bad "the hold left the list or said nothing: $(cat hold.out)"

    printf '%s\n' 'mine' > $list
    hold
    [ "$(cat $list)" = mine ] && ok "a list the user had is left unchanged" ||
      bad "the hold changed the user's list"

    rm -f $list
    printf '%s\n' 'theirs' > theirs
    ln -s "$root/theirs" $list
    hold
    [ -L $list ] && [ "$(cat theirs)" = theirs ] && ok "a symlink at the list's path is left alone" ||
      bad "the hold replaced a symlink"

    # A dry run: a file appeared by other means (the stub copies without
    # `run`), and the hold's own rm must only echo.
    rm -f $list
    seed_dir() { cp fixture-list "$2/hyprland-mimeapps.list"; }
    ( DRY_RUN=1; set -eu; . ./hold.sh ) > hold.out 2>&1 || bad "the dry hold failed: $(cat hold.out)"
    [ -e $list ] && ok "a dry run removes nothing" || bad "a dry run removed the list"

    # control: the hold with its rm deleted must leave the file.
    sed '/run rm -f/d' hold.sh > nohold.sh
    if grep -q 'run rm -f' nohold.sh; then echo "the sed did not remove the hold's rm" >&2; exit 1; fi
    rm -f $list
    seed_dir() { [ -e "$2/hyprland-mimeapps.list" ] || run cp fixture-list "$2/hyprland-mimeapps.list"; }
    ( set -eu; . ./nohold.sh ) > /dev/null 2>&1 || true
    [ -e $list ] || { echo "the hold's rm is not what removes the list, so this check cannot see it (#1342)" >&2; exit 1; }
    rm -f $list

    # ---- #1705: a vanished or stale theme is put right at a switch ----
    # The block from the first-run comment to its closing `fi`, with
    # omarchy-theme-set and the omarchy tree swapped for a stub and a fixture.
    # Each case gets its own HOME and runs under `set -eu` as activation does.
    extract_theme() {
      awk '
        /# First-run theme\./ { on = 1 }
        on { print }
        on && /^[[:space:]]*if \[ -n "\$target" \]; then$/ { match($0, /^[[:space:]]*/); ind = substr($0, 1, RLENGTH); seen = 1 }
        on && seen && $0 == ind "fi" { exit }
      ' "$1" | sed -e "s|/nix/store/[^ \"]*/bin/omarchy-theme-set|$root/theme-set-stub|" -e "s|/nix/store/[^\"]*/themes/|$root/home/omar/themes/|g"
    }
    extract_theme seed.sh > theme.sh
    rehome ${seedTheme} > seed2.sh
    extract_theme seed2.sh > theme2.sh
    for f in theme.sh theme2.sh; do
      grep -q 'no longer exists' $f || { echo "the theme fallback is not in nixarchySeed any more ($f)" >&2; exit 1; }
      grep -q "$root/theme-set-stub" $f || { echo "the theme-set stub did not replace the store path ($f)" >&2; exit 1; }
      grep -q "$root/home/omar/themes/" $f || { echo "the omarchy tree did not move to the fixture ($f)" >&2; exit 1; }
    done
    printf '%s\n' '#!/bin/sh' \
      'printf "%s\n" "$1" >> "$CALLS"' \
      '[ "$STUB_FAIL" = 1 ] && exit 1' \
      'mkdir -p "$HOME/.local/state/omarchy/current/theme"' \
      'printf "%s\n" "$1" > "$HOME/.local/state/omarchy/current/theme.name"' \
      '[ "$STUB_NO_COLORS" = 1 ] || : > "$HOME/.local/state/omarchy/current/theme/colors.toml"' \
      'exit 0' > theme-set-stub
    chmod +x theme-set-stub
    # tcase NAME: a fresh home; blk SCRIPT [VAR=value...] runs the block in it.
    tcase() {
      h=$root/cases/$1
      rm -rf "$h"
      mkdir -p "$h/.local/state/omarchy/current" "$h/omar/themes" "$h/.config/omarchy/themes"
    }
    blk() {
      script=$1; shift
      sed "s|$root/home|$h|g" "$script" > "$h/block.sh"
      rc=0
      ( export HOME="$h" CALLS="$h/calls" "$@"; set -eu; . "$h/block.sh" ) > "$h/out" 2> "$h/err" || rc=$?
    }
    marker() { echo "$h/.local/state/nixarchy/theme-fallback"; }
    has() { grep -qF -- "$1" "$2"; }
    setname() { printf '%s\n' "$1" > "$h/.local/state/omarchy/current/theme.name"; }

    for kind in missing empty blank; do
      tcase first-$kind
      case $kind in
        empty) : > "$h/.local/state/omarchy/current/theme.name" ;;
        blank) printf ' \n' > "$h/.local/state/omarchy/current/theme.name" ;;
      esac
      blk theme.sh
      [ "$rc" = 0 ] && [ "$(cat "$h/calls" 2>/dev/null)" = tokyo-night ] && [ ! -e "$(marker)" ] &&
        ok "a $kind theme.name applies the default and leaves no marker" ||
        bad "a $kind theme.name: rc=$rc calls=$(cat "$h/calls" 2>/dev/null) marker=$(ls "$(marker)" 2>&1)"
    done

    tcase bundled
    setname foo; mkdir "$h/omar/themes/foo"
    blk theme.sh
    [ "$rc" = 0 ] && [ ! -e "$h/calls" ] && [ ! -e "$(marker)" ] && [ ! -s "$h/out" ] && [ ! -s "$h/err" ] &&
      ok "a bundled theme that exists: no call, no marker, no output" ||
      bad "a bundled theme: rc=$rc calls=$(cat "$h/calls" 2>&1) out=$(cat "$h/out" "$h/err")"

    tcase usertheme
    setname foo; mkdir "$h/.config/omarchy/themes/foo"
    blk theme.sh
    [ "$rc" = 0 ] && [ ! -e "$h/calls" ] && [ ! -e "$(marker)" ] &&
      ok "a user theme that exists: no call" ||
      bad "a user theme: rc=$rc calls=$(cat "$h/calls" 2>&1)"

    tcase vanished
    setname gone; mkdir "$h/omar/themes/gruvbox" "$h/omar/themes/tokyo-night"
    blk theme2.sh
    [ "$rc" = 0 ] && [ "$(cat "$h/calls" 2>/dev/null)" = gruvbox ] &&
      [ "$(cat "$(marker)" 2>/dev/null)" = "$(printf 'gone\ngruvbox')" ] &&
      has "theme 'gone' no longer exists; applied 'gruvbox' (#1705)" "$h/out" &&
      ok "a vanished theme gets the configured default, a marker (old, new) and a log line" ||
      bad "a vanished theme: rc=$rc calls=$(cat "$h/calls" 2>&1) marker=$(cat "$(marker)" 2>&1) out=$(cat "$h/out")"

    tcase vanished-default
    setname gone; mkdir "$h/omar/themes/tokyo-night"
    blk theme2.sh
    [ "$rc" = 0 ] && [ "$(cat "$h/calls" 2>/dev/null)" = tokyo-night ] &&
      [ "$(cat "$(marker)" 2>/dev/null)" = "$(printf 'gone\ntokyo-night')" ] &&
      ok "a vanished default falls back to tokyo-night" ||
      bad "a vanished default: rc=$rc calls=$(cat "$h/calls" 2>&1) marker=$(cat "$(marker)" 2>&1)"

    for fault in STUB_FAIL STUB_NO_COLORS; do
      tcase fault-$fault
      setname gone; mkdir "$h/omar/themes/tokyo-night"
      blk theme.sh $fault=1
      [ "$rc" = 0 ] && [ ! -e "$(marker)" ] &&
        has "could not apply 'tokyo-night' in place of vanished theme 'gone'" "$h/err" &&
        ok "$fault: a warning on stderr, the switch goes on, no marker" ||
        bad "$fault: rc=$rc marker=$(ls "$(marker)" 2>&1) err=$(cat "$h/err")"
    done

    tcase dry
    setname gone; mkdir "$h/omar/themes/tokyo-night"
    blk theme.sh DRY_RUN=1
    [ "$rc" = 0 ] && [ ! -e "$h/.local/state/nixarchy" ] && [ ! -e "$h/calls" ] &&
      ! has "no longer exists" "$h/out" && ! has "could not apply" "$h/err" &&
      ok "a dry run writes no marker, creates no state dir and says neither line" ||
      bad "a dry run: rc=$rc out=$(cat "$h/out") err=$(cat "$h/err") state=$(ls -A "$h/.local/state/nixarchy" 2>&1)"

    tcase symlinks
    setname foo; mkdir real-foo-$$ "$h/real"
    ln -s "$h/real" "$h/.config/omarchy/themes/foo"
    blk theme.sh
    [ "$rc" = 0 ] && [ ! -e "$h/calls" ] && [ ! -e "$(marker)" ] &&
      ok "a theme directory that is a resolving symlink counts as existing" ||
      bad "a resolving symlink: rc=$rc calls=$(cat "$h/calls" 2>&1)"
    rm -rf real-foo-$$
    tcase dangling
    setname foo; mkdir "$h/omar/themes/tokyo-night"
    ln -s "$h/nowhere" "$h/.config/omarchy/themes/foo"
    blk theme.sh
    [ "$rc" = 0 ] && [ "$(cat "$h/calls" 2>/dev/null)" = tokyo-night ] && [ -e "$(marker)" ] &&
      ok "a dangling symlinked theme directory is repaired" ||
      bad "a dangling symlink: rc=$rc calls=$(cat "$h/calls" 2>&1)"

    # ---- #1705: the notice hook keeps its marker until the toast was shown ----
    mkdir -p hookstubs
    printf '%s\n' '#!/bin/sh' 'echo "$@" >> "$NOTIFIED"' '[ "$NOTIFY_FAIL" = 1 ] && exit 1' 'exit 0' > hookstubs/notify-send
    chmod +x hookstubs/notify-send
    sed "s|^export PATH=|export PATH=$root/hookstubs:|" ${themeHook} > theme-hook.sh
    hookrun() {
      rc=0
      HOME="$h" NOTIFIED="$h/notified" bash theme-hook.sh > "$h/out" 2>&1 || rc=$?
    }
    tcase hook-ok
    mkdir -p "$h/.local/state/nixarchy"; printf 'gone\ngruvbox\n' > "$(marker)"
    hookrun
    [ "$rc" = 0 ] && [ "$(wc -l < "$h/notified")" = 1 ] && has "'gone'" "$h/notified" && has "'gruvbox'" "$h/notified" && [ ! -e "$(marker)" ] &&
      ok "the hook notifies once and removes the marker" ||
      bad "the hook: rc=$rc notified=$(cat "$h/notified" 2>&1) marker=$(ls "$(marker)" 2>&1)"
    tcase hook-fail
    mkdir -p "$h/.local/state/nixarchy"; printf 'gone\ngruvbox\n' > "$(marker)"
    NOTIFY_FAIL=1 hookrun
    [ "$(wc -l < "$h/notified")" = 1 ] && [ -e "$(marker)" ] &&
      ok "a failed notification keeps the marker for the next login" ||
      bad "failed notify: notified=$(cat "$h/notified" 2>&1) marker=$(ls "$(marker)" 2>&1)"
    tcase hook-none
    hookrun
    [ "$rc" = 0 ] && [ ! -e "$h/notified" ] &&
      ok "no marker, no notification" ||
      bad "no marker: rc=$rc notified=$(cat "$h/notified" 2>&1)"

    # ---- an unreadable plugin list stops the hook ----
    mkdir -p stubs
    printf '#!/bin/sh\nexit 0\n' > stubs/omarchy-shell
    printf '#!/bin/sh\ntouch %s/listed\necho "qt: locale is not UTF-8"\nexit 0\n' "$root" > stubs/omarchy-plugin-list
    printf '#!/bin/sh\necho "$@" >> %s/enabled\n' "$root" > stubs/omarchy-plugin-enable
    printf '#!/bin/sh\necho "$@" >> %s/disabled\n' "$root" > stubs/omarchy-plugin-disable
    printf '#!/bin/sh\ncat > /dev/null\n' > stubs/systemd-cat
    chmod +x stubs/*
    # The hook sets its own PATH with the real omarchy first, so the stubs go
    # in front of THAT; and the list stub leaves a mark, because a hook that
    # exits before the list (a shell that never answers) passes vacuously.
    sed "s|^export PATH=|export PATH=$root/stubs:|" ${hook} > hook.sh
    bash hook.sh > hook.out 2>&1 || bad "the hook failed: $(cat hook.out)"
    [ -e listed ] || { echo "the hook never reached the plugin list; this case tests nothing" >&2; exit 1; }
    [ ! -e enabled ] && ok "an unreadable plugin list enables nothing" ||
      bad "an unreadable plugin list still enabled: $(tr '\n' ' ' < enabled)"
    [ -z "$(ls -A home/.local/state/nixarchy/enabled-once 2>/dev/null)" ] &&
      ok "and marks nothing done, so the next login retries" ||
      bad "an unreadable plugin list wrote once-markers"

    # ---- the flake's safe.directory include survives git's own syntax ----
    # A flake reached through a symlink gets its resolved path written into a
    # git config include, and `#`, `;` and `"` are syntax there: echoed raw,
    # git read the value up to the first `#`. Read it back the way git does.
    real="$root/real # ; \"dir"
    mkdir -p "$real" state
    ln -s "$real" flake-link
    sed -e "s|/etc/nixos|$root/flake-link|g" -e "s|/var/lib/nixarchy|$root/state|g" ${safeDir} > safe-dir.sh
    ( chown() { :; }; . ./safe-dir.sh ) > safe-dir.out 2>&1 || bad "the include step failed: $(cat safe-dir.out)"
    got=$(git config --file state/gitconfig-flake --get safe.directory 2>&1 || true)
    [ "$got" = "$real" ] && ok "a flake path with git config syntax in it reads back whole" ||
      bad "safe.directory read back as: $got"

    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1276)" >&2; exit 1; }
    touch $out
  ''
