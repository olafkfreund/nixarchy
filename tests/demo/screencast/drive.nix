# The driver and the recorder (#930, plan steps 5 and 6).
#
# The driver performs the shot list and writes down WHEN each beat actually
# fired. That second half is the point: sampling the recording at the times
# shots.nix asked for fails on compositor lag, window-open animation and frame
# jitter, so the gate reads observed times instead. Both reviews of the spec
# raised this independently and it is the only reason beats.json exists.
{
  pkgs,
  shots ? import ./shots.nix,
  acts ? import ./acts.nix,
  sessionEnv,
}:
let
  # The beats, as UNIT-SEPARATOR (\037) delimited lines the shell can read
  # without a JSON parser in the loop.
  #
  # Not tab, and this is not taste. Tab is whitespace, and bash collapses runs
  # of whitespace IFS characters into one delimiter -- so an empty field
  # disappears and every later field shifts left. A beat with no `id` but a
  # `route` (install-pick) would have put the route into the id and never
  # opened. Found by testing the gate, which had the identical bug.
  beatLines = pkgs.lib.concatMapStringsSep "\n" (
    b:
    builtins.concatStringsSep "\t" [
      b.label
      b.action
      # Nix renders a float as 2.400000; trimmed so the table and any timing
      # arithmetic read cleanly. sleep accepts either.
      (
        let
          t = toString b.hold;
        in
        if pkgs.lib.hasInfix "." t then
          pkgs.lib.head (builtins.match "([0-9]+\\.[0-9]*[1-9]|[0-9]+)\\.?0*" t)
        else
          t
      )
      (if (b.id or "") == "" then "-" else b.id)
      (if (b.route or "") == "" then "-" else b.route)
      (if (b.command or "") == "" then "-" else b.command)
    ]
  ) shots.beats;

  # The trailing newline is load-bearing. Without it `while read` returns
  # non-zero on the final line and never runs the body for it -- the first real
  # take lost its `endcard` beat and nothing reported a problem: 17 entries for
  # an 18-beat list.
  beatFile = pkgs.writeText "screencast-beats.tsv" (beatLines + "\n");

  # The acting fragments, as one case statement each. Written as a case rather
  # than eval'd from a variable so shellcheck can see them and the script stays
  # readable when something goes wrong mid-take.
  actCase =
    phase:
    pkgs.lib.concatStrings (
      pkgs.lib.mapAttrsToList (id: a: ''
        ${id})
          ${a.${phase} or ":"}
          ;;
      '') acts.acts
    );
in
{
  drive = pkgs.writeShellApplication {
    name = "screencast-drive";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.procps
      pkgs.wtype
    ];
    text = ''
      ${sessionEnv}

      out=''${1:-$PWD}
      mkdir -p "$out"
      beats="$out/beats.json"

      # Monotonic seconds since boot, the same clock the recorder timestamps
      # with. Wall clock would be wrong the moment anything adjusts it, and a
      # recording is exactly when something might.
      now() { cut -d' ' -f1 /proc/uptime; }

      # Every layer-shell surface that is not the bar or the wallpaper -- i.e.
      # an open panel. This is what makes "did the beat open anything?"
      # answerable during the take rather than only by the gate afterwards.
      panels() {
        hyprctl layers -j 2>/dev/null |
          jq -r '[.[].levels | to_entries[].value[]? | .namespace]
                 | map(select(test("^omarchy-(bar|background)$") | not))
                 | join(" ")' 2>/dev/null || true
      }

      omarchy-shell shell ping >/dev/null 2>&1 || {
        echo "screencast-drive: the shell is not reachable." >&2
        echo "OMARCHY_PATH=''${OMARCHY_PATH:-unset} -- it must be the tree the" >&2
        echo "running shell was launched from." >&2
        exit 1
      }

      # The take's own zero. Every observed time below is relative to it, so
      # the gate can seek into the recording without knowing when recording
      # started in wall-clock terms.
      t0=$(now)
      opened_nothing=0
      printf '{"t0":%s,"beats":[' "$t0" > "$beats"
      first=1

      while IFS=$'\t' read -r label action hold id route command; do
        [ -n "$label" ] || continue
        # "-" stands in for an absent field. Tab is whitespace, and bash
        # collapses runs of whitespace IFS characters into one delimiter, so
        # an empty field vanishes and every later one shifts left --
        # install-pick would have put its route into the id and opened
        # nothing. A placeholder cannot collapse.
        [ "$id" != "-" ] || id=""
        [ "$route" != "-" ] || route=""
        [ "$command" != "-" ] || command=""

        # Observed BEFORE the action, because what the gate wants to know is
        # when the panel could first have been on screen -- not when the
        # command returned.
        at=$(now)

        # Whatever this beat needs to exist, made before the panel opens so the
        # panel has something real to show. Every name is demo-*.
        if [ -n "$id" ]; then
          case "$id" in
            ${actCase "before"}
            *) : ;;
          esac
        fi

        case "$action" in
          settle) : ;;
          plugin) nixarchy-plugin "$id" >/dev/null 2>&1 || echo "  (plugin $id did not open)" >&2 ;;
          menu)
            if [ -n "$route" ]; then
              omarchy-menu summon "$route" >/dev/null 2>&1 || echo "  (route $route did not open)" >&2
            else
              omarchy-menu >/dev/null 2>&1 &
            fi
            ;;
          term)
            # setsid, so the terminal outlives this loop's process group the
            # way tests/demo/default.nix's `terminal()` does.
            setsid foot -a screencast.term bash -lc "$command" >/dev/null 2>&1 &
            ;;
          *)
            echo "screencast-drive: unknown action '$action' for beat '$label'" >&2
            exit 1
            ;;
        esac

        [ "$first" = 1 ] || printf ',' >> "$beats"
        first=0
        printf '{"label":"%s","at":%s}' "$label" "$(echo "$at $t0" | awk '{printf "%.2f", $1 - $2}')" >> "$beats"
        echo "  $label at $(echo "$at $t0" | awk '{printf "%.1f", $1 - $2}')s"

        # A plugin beat that opened nothing is a beat the viewer will not see,
        # and the take should say so while it can still be re-run -- not leave
        # it for the gate to find in an hour.
        if [ "$action" = plugin ] || [ "$action" = menu ]; then
          sleep 1
          if [ -z "$(panels)" ]; then
            echo "  (warning: $label opened no panel)" >&2
            opened_nothing=$((opened_nothing + 1))
          fi
          sleep "$(awk -v h="$hold" 'BEGIN { d = h - 1; if (d < 0) d = 0; print d }')"
        else
          sleep "$hold"
        fi

        # Close what the beat opened, so the next starts from the desktop rather
        # than from a stack of panels.
        #
        # wtype, not hyprctl. A shell panel is a layer-shell surface:
        # `killactive` does not touch it, and `sendshortcut ',escape,'` is a
        # SYNTHETIC shortcut that a layer surface holding keyboard focus never
        # receives. wtype goes through the virtual-keyboard protocol, which is
        # the path a real keypress takes -- and a real Escape has always worked.
        case "$action" in
          plugin | menu)
            wtype -k Escape >/dev/null 2>&1 || true
            sleep 0.4
            # If it is still up, say so rather than stacking the next panel on
            # top of it. Namespaces, not a layer COUNT: the bar and the
            # background are layers too, so a count moves 3 to 3 when a panel
            # closes and reads as a failure.
            if [ -n "$(panels)" ]; then
              echo "  (warning: $label left a panel open: $(panels))" >&2
              wtype -k Escape >/dev/null 2>&1 || true
              sleep 0.4
            fi
            ;;
          term) hyprctl dispatch closewindow class:screencast.term >/dev/null 2>&1 || true ;;
          *) : ;;
        esac

        # And undo it. The recorder's trap sweeps as well, for a take that dies
        # between the two.
        if [ -n "$id" ]; then
          case "$id" in
            ${actCase "after"}
            *) : ;;
          esac
        fi
      done < ${beatFile}

      printf '],"duration":%s}\n' "$(echo "$(now) $t0" | awk '{printf "%.2f", $1 - $2}')" >> "$beats"
      if [ "$opened_nothing" -gt 0 ]; then
        echo "screencast-drive: $opened_nothing beat(s) opened no panel -- the take is not usable" >&2
        exit 1
      fi
      echo "screencast-drive: done. Observed beat times in $beats"
    '';
  };

  # The recorder wraps the driver so the two cannot be run out of step: one
  # command starts the capture, drives the take, stops the capture, and leaves
  # beats.json beside the master.
  record = pkgs.writeShellApplication {
    name = "screencast-record";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.procps
    ];
    text = ''
      ${sessionEnv}
      out=''${1:-$PWD/screencast}
      mkdir -p "$out"

      monitor=''${SCREENCAST_MONITOR:-$(hyprctl monitors -j | jq -r '.[0].name')}
      master="$out/master.mkv"

      # MKV while recording and convert afterwards: a kill mid-take leaves a
      # playable MKV, where an MP4 without its moov atom is a lost take.
      # 60fps because a 2.4s montage beat at 30 looks stuttery.
      gpu-screen-recorder -w "$monitor" -f 60 -c mkv -o "$master" &
      rec=$!

      # The restore runs whatever happens to this script -- including SIGHUP,
      # which is what a dropped SSH connection sends and which the first draft
      # of this plan omitted.
      cleanup() {
        kill "$rec" 2>/dev/null || true
        wait "$rec" 2>/dev/null || true
        # Demo objects first: a take killed between a beat's before and after
        # leaves one behind, and every name here is demo-*.
        ${acts.sweep}
        screencast-restore || true
      }
      trap cleanup EXIT INT TERM HUP

      sleep 2  # let the recorder reach steady state before the first beat
      screencast-drive "$out"
      sleep 1

      kill "$rec" 2>/dev/null || true
      wait "$rec" 2>/dev/null || true
      trap - EXIT INT TERM HUP
      screencast-restore

      echo "screencast-record: master at $master"
    '';
  };
}
