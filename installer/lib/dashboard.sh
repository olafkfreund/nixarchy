# The install screen: a wordmark, a bar, and a tip. Nothing else.
#
# Upstream shows no log while installing, and that is a deliberate choice worth
# copying: a wall of store paths tells a person nothing they can act on, and it
# makes a normal install look alarming. The log still exists, in a file, and
# the failure screen puts the tail of it on screen the moment it matters.
#
# shellcheck shell=bash

UI_BAR_CELLS=34

# Progress has two sources and takes whichever is further along.
#
# The honest one counts store paths under the target as nixos-install copies
# them, against the closure's own count -- spliced in at build time, because it
# is known then and guessing it at runtime would mean walking the closure on a
# machine that is busy. The other is a time curve, which exists only so the bar
# moves during partitioning and bootloader installation, when nothing is being
# copied and a frozen bar reads as a hung install.
ui_progress() {
  local elapsed=$1 copied=0 by_paths=0 by_time

  if [ -d /mnt/nix/store ]; then
    copied=$(find /mnt/nix/store -maxdepth 1 -mindepth 1 -printf . 2>/dev/null | wc -c)
    [ "$UI_EXPECTED_PATHS" -gt 0 ] && by_paths=$((copied * 100 / UI_EXPECTED_PATHS))
  fi

  # Approaches but never reaches 95 -- a bar that sits at 100 while the install
  # is still going is worse than one that sits at 94.
  by_time=$((elapsed * 95 / (elapsed + 240)))

  local pct=$by_time
  [ "$by_paths" -gt "$pct" ] && pct=$by_paths
  [ "$pct" -gt 99 ] && pct=99
  echo "$pct"
}

ui_bar() {
  local pct=$1 filled i out=""
  filled=$((pct * UI_BAR_CELLS / 100))
  for ((i = 0; i < UI_BAR_CELLS; i++)); do
    if [ "$i" -lt "$filled" ]; then out+="█"; else out+="░"; fi
  done
  printf '%s' "$out"
}

ui_dashboard_draw() {
  local elapsed=$1 pct tip n idx
  pct=$(ui_progress "$elapsed")

  # A tip every eight seconds, as upstream does. Long enough to read, short
  # enough that a slow install is not one sentence for ten minutes.
  n=$(wc -l <"$UI_TIPS")
  idx=$(((elapsed / 8) % n + 1))
  tip=$(sed -n "${idx}p" "$UI_TIPS")

  ui_init
  ui_clear
  echo
  ui_logo
  ui_centre "\e[1mInstalling nixarchy\e[0m" 19
  echo
  ui_centre "\e[32m$(ui_bar "$pct")\e[0m  ${pct}%" $((UI_BAR_CELLS + 6))
  echo
  ui_centre "\e[90m$tip\e[0m" "${#tip}"
}

ui_dashboard_start() {
  UI_DASH_START=$(date +%s)
  # No cursor while the dashboard owns the screen. It has nowhere sensible to
  # sit -- the screen is redrawn every second -- so it ends up parked in a
  # corner blinking at nothing.
  printf '\e[?25l'
  trap 'printf "\e[?25h"' EXIT
  (
    while :; do
      ui_dashboard_draw $(($(date +%s) - UI_DASH_START))
      sleep 1
    done
  ) &
  UI_DASH_PID=$!
}

ui_dashboard_stop() {
  printf '\e[?25h'
  [ -n "${UI_DASH_PID:-}" ] || return 0
  kill "$UI_DASH_PID" 2>/dev/null || true
  wait "$UI_DASH_PID" 2>/dev/null || true
  UI_DASH_PID=""
}

# Elapsed, the way a person says it.
ui_elapsed() {
  local s=$1
  if [ "$s" -lt 60 ]; then
    printf '%ds' "$s"
  else
    printf '%dm %ds' $((s / 60)) $((s % 60))
  fi
}

# The last screen. Mirrors the greeter deliberately: the same mark in the same
# place, so finishing looks like arriving rather than like the program ending.
ui_finished() {
  local elapsed=$1 username=$2
  ui_init
  ui_clear
  echo
  ui_logo
  ui_centre "\e[1;32mInstalled nixarchy in $(ui_elapsed "$elapsed")\e[0m" $((25 + ${#elapsed}))
  echo
  ui_centre "Reboot, then log in as \e[1m$username\e[0m." $((23 + ${#username}))
  ui_centre "\e[90mYour configuration is /etc/nixos -- a git repository, yours to edit.\e[0m" 67
  echo
}

# When it goes wrong, the log is the only thing worth showing, and it is the
# thing the dashboard has been hiding. Put the tail of it on screen rather than
# leaving a person with a cleared terminal and a failure they cannot describe.
ui_failed() {
  local log=$1 rc=$2
  ui_init
  ui_clear
  echo
  ui_logo
  ui_centre "\e[1;31mnixarchy installation stopped\e[0m" 28
  echo
  ui_left "\e[90mexit $rc -- the last of $log:\e[0m"
  echo
  tail -25 "$log" 2>/dev/null | sed "s/^/$(printf '%*s' "${UI_PAD:-0}" '')/"
  echo
  ui_left "\e[90mThe whole log is at $log. Nothing was rebooted.\e[0m"
  echo
}
