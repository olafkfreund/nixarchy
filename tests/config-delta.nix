{ pkgs, ... }:
# The config delta that goes in every Omarchy bump PR.
#
# modules/home.nix seeds upstream's whole config/ tree into ~/.config, and the
# executables those files name arrive by a completely different route -- which
# is how #202 shipped: config/hypr/xdph.conf named a share picker that nothing
# on NixOS provided, and screen sharing failed everywhere, silently.
#
# So this script has two dangerous silences, not one. "No change to the seeded
# config tree" is what a reader sees when upstream changed nothing AND when the
# file walk stopped finding files; "no file names an executable it did not
# already name" is what they see when nothing new was named AND when the
# reference patterns stopped matching upstream's syntax. Both are checked here
# against a known answer, and the second is what the script's own guard exists
# for.
#
# Directories, not tags, because a check has no network -- the workflow does
# the fetching.
let
  # Shaped like the real tree: hyprland conf, an imv config, a .desktop, lua.
  old = pkgs.runCommand "old-config" { } ''
    mkdir -p $out/hypr $out/imv $out/autostart
    cat > $out/hypr/xdph.conf <<'EOF'
    screencopy {
        custom_picker_binary = hyprland-preview-share-picker
    }
    EOF
    cat > $out/hypr/autostart.lua <<'EOF'
    -- o.launch_on_start("my-service")
    o.launch_on_start("hypridle")
    EOF
    cat > $out/imv/config <<'EOF'
    <Ctrl+e> = exec tensaku-edit "$imv_current_file"
    EOF
    cat > $out/autostart/print-applet.desktop <<'EOF'
    [Desktop Entry]
    Exec=system-config-printer-applet
    EOF
    cat > $out/goes-away.conf <<'EOF'
    exec-once = doomed-daemon
    EOF
  '';

  # xdph.conf gains a second name, autostart.lua gains one, a file appears and
  # a file disappears -- and hypr/autostart.lua keeps the name it already had,
  # which must NOT be reported as new.
  new = pkgs.runCommand "new-config" { } ''
    mkdir -p $out/hypr $out/imv $out/autostart
    cat > $out/hypr/xdph.conf <<'EOF'
    screencopy {
        custom_picker_binary = hyprland-preview-share-picker
    }
    exec-once = xdph-warmup
    EOF
    cat > $out/hypr/autostart.lua <<'EOF'
    -- o.launch_on_start("my-service")
    o.launch_on_start("hypridle")
    o.launch_on_start("omarchy-battery-monitor")
    EOF
    cat > $out/imv/config <<'EOF'
    <Ctrl+e> = exec tensaku-edit "$imv_current_file"
    EOF
    cat > $out/autostart/print-applet.desktop <<'EOF'
    [Desktop Entry]
    Exec=system-config-printer-applet
    EOF
    mkdir -p $out/herdr
    cat > $out/herdr/config.toml <<'EOF'
    command: herdr-agent
    EOF
  '';

  # Same files, same contents, written in a different order: not a change.
  same = pkgs.runCommand "same-config" { } ''
    cp -r ${old} $out
    chmod -R u+w $out
  '';

  # A tree where the reference patterns match nothing. Stands in for the day a
  # bump changes the syntax under them: the script must refuse rather than
  # report a quiet release.
  mute = pkgs.runCommand "mute-config" { } ''
    mkdir -p $out
    echo 'colour = "#ff0000"' > $out/theme.toml
  '';
in
pkgs.runCommand "nixarchy-config-delta"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      findutils
      gnugrep
      gnused
      gawk
    ];
  }
  ''
    delta=${../.github/scripts/omarchy-config-delta.sh}
    fail=0

    report=$(bash "$delta" ${old} ${new} v4.0.1 v4.0.2)

    # The file walk, in all three directions.
    added_block=$(echo "$report" | sed -n '/\*\*Added\*\*/,/\*\*Removed\*\*/p')
    echo "$added_block" | grep -q 'config/herdr/config.toml' || {
      echo "config delta: a new file is missing from Added" >&2
      fail=1
    }
    removed_block=$(echo "$report" | sed -n '/\*\*Removed\*\*/,/\*\*Changed\*\*/p')
    echo "$removed_block" | grep -q 'config/goes-away.conf' || {
      echo "config delta: a deleted file is missing from Removed" >&2
      fail=1
    }
    changed_block=$(echo "$report" | sed -n '/\*\*Changed\*\*/,/newly name/p')
    for c in config/hypr/xdph.conf config/hypr/autostart.lua; do
      echo "$changed_block" | grep -q "$c" || {
        echo "config delta: edited file $c is missing from Changed" >&2
        fail=1
      }
    done

    # A file nobody touched belongs in no list at all.
    echo "$report" | grep -q 'print-applet' && {
      echo "config delta: an untouched file was reported as a change" >&2
      fail=1
    }

    # The half #202 turns on: names that are NEW, and only those.
    names=$(echo "$report" | sed -n '/newly name/,$p')
    for want in xdph-warmup omarchy-battery-monitor herdr-agent; do
      echo "$names" | grep -q "$want" || {
        echo "config delta: newly named executable $want was not reported" >&2
        fail=1
      }
    done
    # hypridle was named by the same file before this release, and
    # tensaku-edit's file did not change. Reporting either would bury the
    # three above in noise a reviewer has already read.
    for quiet in hypridle tensaku-edit hyprland-preview-share-picker; do
      echo "$names" | grep -q "$quiet" && {
        echo "config delta: $quiet was named before this release and is not new" >&2
        fail=1
      }
    done
    # The commented sample in autostart.lua names nothing.
    echo "$names" | grep -q 'my-service' && {
      echo "config delta: a commented-out sample was read as a reference" >&2
      fail=1
    }

    # Silence has to mean silence.
    quiet=$(bash "$delta" ${same} ${old} v1 v2)
    echo "$quiet" | grep -q 'No change to the seeded config tree' || {
      echo "config delta: an unchanged tree was reported as a change" >&2
      echo "$quiet" >&2
      fail=1
    }

    # And a broken scan must not look like silence. This is the case the
    # script's own guard exists for: every reference pattern is a grep against
    # upstream's file layout, and a grep that matches nothing passes quietly.
    if bash "$delta" ${old} ${mute} v1 v2 > mute.out 2>&1; then
      echo "config delta: a tree naming no executable at all was accepted" >&2
      cat mute.out >&2
      fail=1
    else
      grep -q 'stopped matching' mute.out || {
        echo "config delta: the empty-scan guard fired without saying why" >&2
        cat mute.out >&2
        fail=1
      }
    fi

    [ "$fail" -eq 0 ] || {
      echo >&2
      echo "What the config delta actually printed:" >&2
      echo "$report" >&2
      exit 1
    }

    echo "the config delta names what moved in the seeded tree, names the"
    echo "executables that arrived with it, and refuses to be quiet when its"
    echo "own patterns stop matching"
    touch $out
  ''
