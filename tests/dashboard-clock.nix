{ pkgs, ... }:
# The install dashboard, against a clock that does not only go forwards.
#
# Reported by a user as a screenful of sed's usage text drawn over the
# installer: "sed: invalid option -- '1'". The tip line picks its tip with
#
#   idx=$(((elapsed / 8) % n + 1))
#   tip=$(sed -n "${idx}p" "$UI_TIPS")
#
# and elapsed is `now - UI_DASH_START`, a difference against a time read
# earlier. When the clock moves BACKWARDS mid-install that goes negative, idx
# with it, and sed is handed `-11p` -- which it reads as options, not a script.
#
# The clock moving backwards during an install is the ordinary case, not an
# exotic one: the machine has an unset or wrong RTC, the installer asks for a
# timezone, and NTP corrects it while this is drawing. It never happens in the
# VM checks because their clocks are stable, which is precisely why this
# needed a check of its own rather than being caught by checks.install.
#
# The second failure is worse and was never reported, because it kills the
# drawer instead of misprinting: ui_progress computes
# `elapsed * 95 / (elapsed + 240)`, and elapsed = -240 is a division by zero.
#
# So the assertions below drive the real functions across a rewound clock and
# demand clean output -- not that the numbers are any particular value, which
# is a decoration, but that nothing errors.
let
  dashboard = ../installer/lib/dashboard.sh;
  ui = ../installer/lib/ui.sh;
  tips = ../installer/brand/tips.txt;
  logo = ../installer/brand/logo.txt;
  logoCompact = ../installer/brand/logo-compact.txt;
in
pkgs.runCommand "nixarchy-dashboard-clock"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnused
      pkgs.util-linux
    ];
  }
  ''
    export UI_TIPS=${tips}
    export UI_LOGO=${logo}
    export UI_LOGO_WIDE=${logo}
    export UI_LOGO_COMPACT=${logoCompact}
    export UI_EXPECTED_PATHS=1000
    export UI_PAD=0
    fail=0

    # The offsets that matter. -240 is not arbitrary: it is the exact value
    # that makes ui_progress's divisor zero, and a clamp that stops one short
    # of it would pass every other case and still take the drawer down.
    for skew in 0 -1 -8 -100 -239 -240 -241 -3600; do
      res=$(
        script -qec "
          . ${ui}
          . ${dashboard}
          ui_dashboard_start
          # Rewind the clock under the running dashboard: start was read at a
          # wall time this now precedes, which is what NTP does to it.
          UI_DASH_START=\$(( \$(date +%s) - ($skew) ))
          UI_DASH_CHANGED=\$UI_DASH_START
          ui_dashboard_tick
        " /dev/null 2>&1
      ) || true

      case "$res" in
        *"invalid option"*)
          echo "skew=$skew: sed was handed a negative line number" >&2
          echo "  this is the reported bug -- the tip index went below 1" >&2
          fail=1 ;;
      esac
      case "$res" in
        *"division by zero"*)
          echo "skew=$skew: ui_progress divided by zero" >&2
          echo "  elapsed reached -240, so (elapsed + 240) is 0" >&2
          fail=1 ;;
      esac
      case "$res" in
        *"Usage: sed"*|*"unary operator expected"*|*"integer expression"*)
          echo "skew=$skew: the drawer errored on a rewound clock" >&2
          fail=1 ;;
      esac
      echo "  skew=$skew drew clean"
    done

    # And the tips file itself, since the index is computed modulo its length:
    # an empty one makes `% n` a division by zero of its own.
    empty=$(mktemp)
    res=$(
      script -qec "
        . ${ui}
        . ${dashboard}
        UI_TIPS=$empty
        ui_dashboard_start
        ui_dashboard_tick
      " /dev/null 2>&1
    ) || true
    case "$res" in
      *"division by zero"*|*"invalid option"*)
        echo "an empty tips file takes the drawer down" >&2
        fail=1 ;;
      *) echo "  an empty tips file draws clean" ;;
    esac

    [ "$fail" = 0 ] || { echo "the dashboard does not survive a clock that goes backwards" >&2; exit 1; }
    echo "the install dashboard survives a rewound clock"
    touch $out
  ''
