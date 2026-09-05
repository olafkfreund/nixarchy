# The install screen: a wordmark, a bar, and a tip. Nothing else.
#
# Upstream shows no log while installing, and that is a deliberate choice worth
# copying: a wall of store paths tells a person nothing they can act on, and it
# makes a normal install look alarming. The log still exists, in a file, and
# the failure screen puts the tail of it on screen the moment it matters.
#
# shellcheck shell=bash

UI_BAR_CELLS=34

# How long the log may sit still before the bar stops advancing, and before
# the dashboard says so out loud. Two thresholds because they answer two
# different questions: 30 seconds of silence is ordinary (one large
# derivation, one slow disk sync) and only means the curve should stop
# guessing; three minutes is when a person watching starts wondering whether
# to reboot, and rebooting mid-install is how a recoverable stall becomes an
# unrecoverable one.
UI_STALL_FREEZE=30
UI_STALL_SAY=180

# Progress has two sources and takes whichever is further along.
#
# The honest one counts store paths under the target as nixos-install copies
# them, against the closure's own count -- spliced in at build time, because it
# is known then and guessing it at runtime would mean walking the closure on a
# machine that is busy. The other is a time curve, which exists only so the bar
# moves during partitioning and bootloader installation, when nothing is being
# copied and a frozen bar reads as a hung install.
ui_progress() {
  local elapsed=$1 stall=${2:-0} copied=0 by_paths=0 by_time

  if [ -d /mnt/nix/store ]; then
    copied=$(find /mnt/nix/store -maxdepth 1 -mindepth 1 -printf . 2>/dev/null | wc -c)
    [ "$UI_EXPECTED_PATHS" -gt 0 ] && by_paths=$((copied * 100 / UI_EXPECTED_PATHS))
  fi

  # The time curve only advances while the log does. It exists so the bar
  # moves through phases that copy nothing -- but that assumes the install is
  # doing SOMETHING. The phases write only to the log by construction, so a
  # log that has stopped growing is an install that has stopped doing
  # observable work, and a percentage that keeps creeping toward 95 over a
  # stopped log is a lie with a progress bar on it: the person watching 87%
  # has no basis for choosing between "slow" and "wedged". Stalled time is
  # subtracted, so the bar freezes where the log stopped -- a frozen bar is
  # at least not a claim of progress.
  if [ "$stall" -gt "$UI_STALL_FREEZE" ]; then
    elapsed=$((elapsed - stall + UI_STALL_FREEZE))
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
  local elapsed=$1 stall=${2:-0} pct tip n idx
  pct=$(ui_progress "$elapsed" "$stall")

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
  if [ "$stall" -ge "$UI_STALL_SAY" ]; then
    # Said out loud, in the tip's place, because the tip is the one line a
    # person watching actually reads. What they most need to hear is that
    # waiting is safe and rebooting is not: a stall this long is usually a
    # slow download, and 20-minute cache stalls that ended fine have been
    # watched from the outside, indistinguishable from a hang.
    local said
    said="Nothing has reached the log in $(ui_elapsed "$stall")."
    ui_centre "\e[33m$said\e[0m" "${#said}"
    said="Usually a slow download; waiting is safe. Ctrl-C stops and shows the log."
    ui_centre "\e[90m$said\e[0m" "${#said}"
  else
    ui_centre "\e[90m$tip\e[0m" "${#tip}"
  fi
}

# One frame: measure the log, then draw. Split from the redraw loop so the
# measurement -- the part that tells "still working" from "stopped" -- can be
# driven by a test one tick at a time, without an infinite loop on a timer.
#
# The log is the right thing to watch because it is the ONLY thing the
# install phases write to: main() redirects the whole chain into it, and the
# dashboard deliberately hides it. So the drawer, the one process watching
# from outside, is the one that can notice it has stopped.
ui_dashboard_tick() {
  local now size
  now=$(date +%s)
  if [ -n "${UI_DASH_LOG:-}" ]; then
    size=$(wc -c 2>/dev/null <"$UI_DASH_LOG") || size=-1
    if [ "$size" != "$UI_DASH_SIZE" ]; then
      UI_DASH_SIZE=$size
      UI_DASH_CHANGED=$now
    fi
  else
    # Nothing to measure. Claiming a stall over a log nobody named would be
    # the same lie in the other direction.
    UI_DASH_CHANGED=$now
  fi
  ui_dashboard_draw $((now - UI_DASH_START)) $((now - UI_DASH_CHANGED))
}

ui_dashboard_start() {
  UI_DASH_START=$(date +%s)
  UI_DASH_LOG=${1:-}
  UI_DASH_SIZE=""
  UI_DASH_CHANGED=$UI_DASH_START
  # No cursor while the dashboard owns the screen. It has nowhere sensible to
  # sit -- the screen is redrawn every second -- so it ends up parked in a
  # corner blinking at nothing.
  printf '\e[?25l'
  trap 'printf "\e[?25h"' EXIT
  (
    while :; do
      ui_dashboard_tick
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

  # One button, because there is exactly one thing left to do. Telling somebody
  # to reboot and leaving them at a prompt makes them find the command; the
  # install knows it, so it offers it.
  #
  # Skipped when nobody is watching: checks.install finishes here, and a
  # prompt would hang the test rather than fail it.
  ui_interactive || return 0
  local choice
  choice=$(printf '%s\n' "Reboot now" "Leave it running" |
    gum choose --padding "$(ui_gum_pad)" --header "") || return 0
  if [ "$choice" = "Reboot now" ]; then
    systemctl reboot
  fi
  return 0
}

# When it goes wrong, the log is the only thing worth showing, and it is the
# thing the dashboard has been hiding. Put the tail of it on screen rather than
# leaving a person with a cleared terminal and a failure they cannot describe.
ui_failed() {
  local log=$1 rc=$2 target_log=${3:-}
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
  # The path above is on the live system and goes away with it. If a copy
  # reached the disk, say so -- that is the one a person can still read after
  # the reboot this screen is about to offer them, and not saying it is how
  # somebody ends up with an unbootable machine and no diagnostic (#239).
  if [ -n "$target_log" ]; then
    ui_left "\e[90mA copy is on the new system at $target_log, readable from a"
    ui_left "\e[90mlive USB if this machine will not boot.\e[0m"
  fi
  echo

  # Twenty-five lines is enough to recognise a failure and rarely enough to
  # diagnose one, so offer the rest rather than making somebody remember a
  # path and a pager on a machine with no desktop yet.
  #
  # A loop: reading the log should return here, not end the installer. Only
  # rebooting, powering off or leaving on purpose gets out.
  ui_interactive || return 0
  local choice
  while :; do
    choice=$(printf '%s\n' \
      "View the whole log" "Open a shell" "Reboot" "Power off" |
      gum choose --padding "$(ui_gum_pad)" --header "What now?") || return 0
    case $choice in
      "View the whole log")
        # gum's pager, not less: gum is already a dependency and less is not,
        # and a live medium is a poor place to discover a missing binary.
        gum pager <"$log" || true
        ;;
      "Open a shell")
        ui_left "\e[90mThe install is stopped. Type exit to come back here.\e[0m"
        echo
        "${SHELL:-bash}" || true
        ;;
      "Reboot") systemctl reboot; return 0 ;;
      "Power off") systemctl poweroff; return 0 ;;
      *) return 0 ;;
    esac
  done
}
