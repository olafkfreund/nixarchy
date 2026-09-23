# Recording a real desktop, as a script rather than an afternoon (#930).
#
# tests/demo/ already automates the VM-recorded GIFs end to end. The
# real-desktop path was only ever written down -- docs/AGENTS.md prescribes
# wl-screenrec and a composition, as prose -- so every hand-recorded GIF in
# docs/img/features/ was made once, by a person, and cannot be reproduced by
# running anything.
#
# The dangerous half is not the recording. It is that preparing somebody's
# live desktop changes it, and the machine has to come back. Everything about
# prep/restore below is shaped by that: refuse rather than mutate, snapshot
# before touching, verify on the way back, and never trust the happy path.
{
  pkgs,
  acts ? import ./acts.nix,
}:
let
  # Where the snapshot lives. Under XDG state rather than /tmp: a reboot must
  # not lose the only copy of somebody's real desktop.
  stateDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/screencast";

  # The environment a command needs to reach a running session from outside it.
  #
  # tests/demo/default.nix's `user()` re-exports four variables and they are
  # all still needed. OMARCHY_PATH is the fifth and the one that actually bit:
  # omarchy-shell selects the instance with `qs ipc -p "$OMARCHY_PATH/shell"`,
  # so it must be the tree the shell was LAUNCHED from. A session that predates
  # a rebuild holds an older store path than an SSH shell inherits, the two
  # never match, and the symptom is "omarchy-shell is not running" against a
  # shell that is plainly running. Measured on razer, #930.
  #
  # Derived from the running process, never from the environment, so a rebuild
  # without a re-login cannot silently break the harness.
  sessionEnv = ''
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    # Globs rather than `ls | grep`: shellcheck refuses the latter, and a glob
    # is what omarchy-shell itself uses to find the socket.
    for sock in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do
      case "$sock" in
        *.lock | *'*') continue ;;
      esac
      WAYLAND_DISPLAY=$(basename "$sock")
      export WAYLAND_DISPLAY
      break
    done

    for sig in "$XDG_RUNTIME_DIR"/hypr/*; do
      [ -d "$sig" ] || continue
      HYPRLAND_INSTANCE_SIGNATURE=$(basename "$sig")
      export HYPRLAND_INSTANCE_SIGNATURE
    done

    shell_tree=$(pgrep -af quickshell | grep -oE '\-p [^ ]+' | head -1 | cut -d' ' -f2 || true)
    if [ -n "$shell_tree" ]; then
      export OMARCHY_PATH="''${shell_tree%/shell}"
    fi
  '';

  common = [
    pkgs.jq
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.procps
  ];
in
rec {
  # Exported so drive.nix takes the same environment rather than re-deriving
  # it, and so `all` below can wire the whole harness in one place.
  inherit sessionEnv;

  # Everything, as one package. This is what gets copied to a machine with a
  # session on it.
  all = pkgs.symlinkJoin {
    name = "screencast";
    paths = [
      prep
      restore
      recover
    ]
    ++ (
      let
        d = import ./drive.nix { inherit pkgs sessionEnv; };
        e = import ./edit.nix { inherit pkgs; };
      in
      [
        d.drive
        d.record
        e.edit
      ]
    );
  };

  # ---------------------------------------------------------------- prep ----
  prep = pkgs.writeShellApplication {
    name = "screencast-prep";
    runtimeInputs = common;
    text = ''
      ${sessionEnv}
      state="${stateDir}"

      # A stale snapshot means a previous take died. Overwriting it would
      # destroy the only copy of the real desktop, so this refuses and names
      # the way out rather than helping itself.
      if [ -e "$state/manifest.json" ]; then
        echo "screencast-prep: a snapshot from an earlier take is still here:" >&2
        echo "  $state/manifest.json" >&2
        echo "The desktop may still be in recording state. Run screencast-restore," >&2
        echo "or screencast-recover if no take is running." >&2
        exit 1
      fi

      omarchy-shell shell ping >/dev/null 2>&1 || {
        echo "screencast-prep: the shell is not reachable." >&2
        echo "OMARCHY_PATH is ''${OMARCHY_PATH:-unset}; it must be the tree the" >&2
        echo "running shell was launched from, not the one this shell inherited." >&2
        exit 1
      }

      # Prep refuses rather than closing anything. Closing somebody's windows
      # is not recoverable at any price, so the operator closes their own work
      # deliberately -- #930's review found this and it is the whole reason
      # prep is narrow.
      windows=$(hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.mapped)] | length' || echo 0)
      if [ "$windows" -gt 0 ]; then
        echo "screencast-prep: $windows window(s) are open. Close them first:" >&2
        hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.mapped) | "  \(.class): \(.title)"' >&2
        exit 1
      fi

      mkdir -p "$state"
      cp ~/.config/omarchy/shell.json "$state/shell.json"
      sha256sum "$state/shell.json" | cut -d' ' -f1 > "$state/shell.json.sha256"

      # Everything prep is about to change, recorded before it changes it.
      # Omarchy's own widgets (omarchy.*) and nixarchy's stay; only third-party
      # marketplace plugins are hidden, and keystroke is kept deliberately --
      # a video whose middle act is keybindings is better for showing them.
      # The KINDS are recorded, not just the ids, because putting a plugin back
      # depends on what it is. `omarchy plugin enable <id> right` places a bar
      # WIDGET; a plugin whose kind is `bar` replaces the bar, and the same
      # call with a placement leaves it disabled. Measured: skal.bar failed to
      # come back until the argument was dropped, and then answered "Now using
      # skal.bar as the bar" (#930).
      omarchy-shell shell listPlugins 2>/dev/null | jq -r '
        [ .[]? | select(.enabled == true)
               | select(.id | test("^omarchy\\.|^nixarchy\\.|olafkfreund") | not)
               | select(.id != "evindor.keystroke")
               | { id: .id, kinds: (.kinds // []) } ]' > "$state/disabled.json"

      hide=$(jq -r '.[].id' "$state/disabled.json")

      jq -n --slurpfile d "$state/disabled.json" \
        --arg theme "$(omarchy-theme-current 2>/dev/null || echo unknown)" \
        '{disabled: $d[0], theme: $theme}' > "$state/manifest.json"

      for id in $hide; do
        echo "  hiding $id"
        omarchy plugin disable "$id" >/dev/null 2>&1 || echo "  (could not disable $id)" >&2
      done

      # What the take needs to exist before the camera rolls. razer has no
      # devenv projects, so that panel would open on an empty list -- and
      # scaffolding one inside its own beat records a spinner.
      ${acts.stage}

      omarchy-toggle-idle stay-awake >/dev/null 2>&1 || true
      echo "screencast-prep: ready. $(printf '%s' "$hide" | grep -c . || true) plugin(s) hidden."
      echo "Restore with: screencast-restore"
    '';
  };

  # ------------------------------------------------------------- restore ----
  restore = pkgs.writeShellApplication {
    name = "screencast-restore";
    runtimeInputs = common;
    text = ''
      ${sessionEnv}
      state="${stateDir}"

      [ -e "$state/manifest.json" ] || { echo "screencast-restore: nothing to restore."; exit 0; }

      # Through the shell's own IPC, never by writing shell.json. The shell
      # rewrites that file from memory and watches it (modules/AGENTS.md), so a
      # file written under a running shell is overwritten by it -- prep avoids
      # that and restore must too, or the asymmetry is a bug.
      # A bar-kind plugin takes no placement; a widget does. Passing `right` to
      # a bar leaves it disabled, which is how skal.bar failed to come back the
      # first time this was run for real.
      jq -r '.disabled[] | "\(.id)\t\(.kinds | join(","))"' "$state/manifest.json" |
        while IFS=$'\t' read -r id kinds; do
          [ -n "$id" ] || continue
          echo "  restoring $id"
          case ",$kinds," in
            *,bar,*) omarchy plugin enable "$id" >/dev/null 2>&1 || echo "  (could not enable $id)" >&2 ;;
            *) omarchy plugin enable "$id" right >/dev/null 2>&1 || echo "  (could not enable $id)" >&2 ;;
          esac
        done

      omarchy-toggle-idle resume >/dev/null 2>&1 || true

      # Settle before reading back: an immediate comparison would pass on
      # exactly the race this is guarding against, because the shell has not
      # written its state yet.
      sleep 3

      want=$(cat "$state/shell.json.sha256")
      got=$(sha256sum ~/.config/omarchy/shell.json | cut -d' ' -f1)
      if [ "$want" = "$got" ]; then
        echo "screencast-restore: shell.json is byte-identical to before."
        rm -rf "$state"
        exit 0
      fi

      # Not identical is not necessarily wrong -- the shell rewrites the file
      # and key order or whitespace can differ. So compare what it MEANS.
      if jq -S . "$state/shell.json" > "$state/.before.norm" 2>/dev/null \
         && jq -S . ~/.config/omarchy/shell.json > "$state/.after.norm" 2>/dev/null \
         && cmp -s "$state/.before.norm" "$state/.after.norm"; then
        echo "screencast-restore: shell.json differs byte for byte but is equivalent."
        rm -rf "$state"
        exit 0
      fi

      echo "screencast-restore: shell.json did NOT come back." >&2
      echo "The snapshot is kept at $state/shell.json -- nothing has been deleted." >&2
      echo "Differences:" >&2
      diff "$state/.before.norm" "$state/.after.norm" >&2 || true
      exit 1
    '';
  };

  # ------------------------------------------------------------- recover ----
  # For the signals no trap catches: SIGKILL, OOM, power loss, a machine that
  # rebooted mid-take. prep's refusal message names this command.
  recover = pkgs.writeShellApplication {
    name = "screencast-recover";
    runtimeInputs = common;
    text = ''
      ${sessionEnv}
      state="${stateDir}"
      [ -e "$state/manifest.json" ] || { echo "screencast-recover: nothing to recover."; exit 0; }

      if pgrep -f screencast-drive >/dev/null 2>&1; then
        echo "screencast-recover: a take is still running. Stop it first." >&2
        exit 1
      fi
      echo "screencast-recover: restoring from a snapshot left by an earlier take."
      exec screencast-restore
    '';
  };
}
