{ pkgs, ... }:
# The installer's interactive half, which nothing else looks at.
#
# ui_interactive() is `[ -z "$answers_file" ] && [ -t 0 ]`, and every harness
# passes --answers: checks.install does, installer-vm does. So no gum widget
# had ever been drawn under test, and the first time one was, it panicked in
# Go on a terminal somebody was mid-install on (#133).
#
# Not a VM. gum needs a pty, not a machine, so `script` supplies one and this
# finishes in seconds.
let
  ui = ../installer/lib/ui.sh;

  # A serial console at its narrowest, the classic 80, a framebuffer console,
  # a maximised terminal emulator.
  widths = [
    40
    60
    80
    100
    132
    200
    240
  ];

  # What ui_dimension answers on the framebuffer path -- a guess, and often a
  # much larger one than the terminal really is.
  guesses = [
    182
    240
    400
  ];

  placeholder = "Alphanumeric, no spaces (like dhh)";
  prompt = "Username> ";
  needs = builtins.stringLength placeholder + builtins.stringLength prompt;
in
pkgs.runCommand "nixarchy-installer-ui"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.gum
      pkgs.util-linux
      pkgs.ncurses
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
        set -u
        export TERM=linux
        export UI_SH=${ui}
        fail=0

        # A file rather than shell inlined into `script -c`: the stub below is a
        # function inside a Nix string inside a -c argument, and at that depth the
        # quoting stops being reviewable. The first attempt at this silently
        # produced an empty UI_PAD, and every assertion then "passed" on nothing.
        cat >probe.sh <<'PROBE'
        . "$UI_SH"
        if [ -n "''${STUB_COLS:-}" ]; then
          # ui_dimension's framebuffer path: answer with a guess, and flag it.
          ui_dimension() {
            UI_SIZE_UNCONFIRMED=1
            if [ "$1" = cols ]; then echo "$STUB_COLS"; else echo 24; fi
          }
        fi
        ui_init >/dev/null 2>&1
        printf 'PAD=%s' "''${UI_PAD:-EMPTY}"
    PROBE

        probe() { # width, stub
          STUB_COLS=''${2:-} script -qec "stty cols $1 rows 24; bash probe.sh" /dev/null 2>/dev/null |
            grep -o 'PAD=[0-9]*' | head -1 | cut -d= -f2
        }

        draws_clean() { # width, pad -> 0 if no panic
          local r
          r=$(script -qec "stty cols $1 rows 24; timeout 5 gum input --padding '0 0 0 '$2 \
                --placeholder '${placeholder}' --prompt '${prompt}'" /dev/null 2>&1 || true)
          ! printf '%s' "$r" | grep -qE 'Caught panic|len out of range|runtime error'
        }

        # ---- every width a console might actually be -------------------------
        for cols in ${toString widths}; do
          pad=$(probe "$cols")
          [ -n "$pad" ] || { echo "ui_init produced no UI_PAD at $cols columns" >&2; fail=1; continue; }

          # The contract: padding never takes room the terminal had to give. On a
          # console narrower than the prompt there is nothing padding can do, so
          # what is asserted is that it does not make it worse.
          room=$((cols - pad)); want=${toString needs}
          [ "$want" -gt "$cols" ] && want=$cols
          if [ "$room" -lt "$want" ]; then
            echo "at $cols columns UI_PAD=$pad leaves $room, and $want was available" >&2
            fail=1
          fi
          draws_clean "$cols" "$pad" || { echo "gum panicked at $cols columns, UI_PAD=$pad" >&2; fail=1; }
          echo "  $cols cols -> UI_PAD=$pad, $room for content, drew clean"
        done

        # ---- the case that actually produced #133 ----------------------------
        #
        # A real pty always reports its true width, so the matrix above passes
        # with the bug fully reintroduced -- it did, which is why this exists.
        # What went wrong was a width that was a GUESS: the VT may not use the
        # whole framebuffer, so the number can be far larger than the terminal gum
        # measures for itself, and padding centred on it is wider than the screen.
        for stub in ${toString guesses}; do
          pad=$(probe 80 "$stub")
          if [ -z "$pad" ] || [ "$pad" != 0 ]; then
            echo "an unconfirmed width of $stub gave UI_PAD=''${pad:-EMPTY}, not 0" >&2
            echo "  that number is a guess about the console; centring on it is what" >&2
            echo "  pads wider than the real terminal and panics gum (#133)" >&2
            fail=1
            pad=''${pad:-0}
          fi
          draws_clean 80 "$pad" || {
            echo "gum panicked on 80 columns with an unconfirmed width of $stub" >&2; fail=1; }
          echo "  unconfirmed $stub -> UI_PAD=$pad on an 80-column terminal, drew clean"
        done

        [ "$fail" = 0 ] || { echo "the interactive screens do not survive every width" >&2; exit 1; }
        echo "gum renders at ${toString (builtins.length widths)} widths and ignores ${toString (builtins.length guesses)} bad guesses"
        touch $out
  ''
