{ pkgs, ... }:
# Two nixarchy-verify sections, driven against fixtures: the MicroVM guests
# loop (#1417) and the Bluetooth pairability row (#1418).
#
# The verify-boxes.nix pattern: sed lifts the section out of the shipped
# script, the system paths are rewritten to fixture directories, and it is
# sourced with stubs. Each rule is asserted in BOTH shapes, because one
# shape alone cannot fail on the other: a declared guest that dangles must
# stay a failure while a leftover is only a note, and a pairable adapter
# with no known agent must stay a failure while blueman's is a note.
pkgs.runCommand "nixarchy-verify-sections"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail
    src=${../pkgs/verify.sh}
    export HOME=$TMPDIR/home
    mkdir -p "$HOME"

    # <name> <start marker> <end marker>: refuses an empty extraction, so a
    # renamed marker fails here instead of testing nothing.
    lift() {
      test "$(grep -c "^# ---- $2 " "$src")" -eq 1 || { echo "FAIL: marker '$2' missing"; exit 1; }
      test "$(grep -c "^# ---- $3 " "$src")" -eq 1 || { echo "FAIL: marker '$3' missing"; exit 1; }
      sed -n "/^# ---- $2 /,/^# ---- $3 /{ /^# ---- $2 /d; /^# ---- $3 /d; p; }" "$src" \
        | sed -e "s|/var/lib/microvms|$TMPDIR/vms|g" \
              -e "s|/nix/var/nix/gcroots/microvm|$TMPDIR/gcroots|g" \
              -e "s|/sys/class/bluetooth|$TMPDIR/bt|g" > "$TMPDIR/$1.sh"
      test "$(wc -l < "$TMPDIR/$1.sh")" -gt 10 || { echo "FAIL: '$1' extraction is empty"; exit 1; }
    }
    lift guests 'microvm guests' theming
    lift bluetooth bluetooth radios
    grep -Fq 'no longer declared' "$TMPDIR/guests.sh" || { echo 'FAIL: guests section lost the leftover rule'; exit 1; }

    head_() { :; }
    ok() { printf 'OK: %s\n' "$1"; }
    hmm() { printf 'NOTE: %s\n' "$1"; }
    bad() { printf 'BAD: %s\n' "$1"; }
    say_dim() { :; }
    timeout() { shift; "$@"; }
    has() { # <log> <line>
      grep -Fxq -- "$2" "$TMPDIR/$1.log" || { echo "FAIL: expected '$2' in $1:"; cat "$TMPDIR/$1.log"; exit 1; }
    }
    hasnot() {
      if grep -Fq -- "$2" "$TMPDIR/$1.log"; then echo "FAIL: '$2' in $1:"; cat "$TMPDIR/$1.log"; exit 1; fi
    }

    # ---- guests: declared / leftover / imperative, all dangling
    for n in declared leftover imperative; do
      mkdir -p "$TMPDIR/vms/$n"
      ln -s /nonexistent "$TMPDIR/vms/$n/current"
    done
    mkdir -p "$TMPDIR/gcroots"; touch "$TMPDIR/gcroots/imperative"
    systemctl() { [ "$1 $2" = "cat install-microvm-declared.service" ]; }
    source "$TMPDIR/guests.sh" > "$TMPDIR/guests.log"
    has guests 'BAD: declared: current is a dangling link'
    has guests 'BAD: imperative: current is a dangling link'
    has guests 'NOTE: leftover: no longer declared'
    hasnot guests 'BAD: leftover'
    hasnot guests 'NOTE: declared'
    echo 'a declared guest that dangles fails; a leftover is a note'

    # ---- bluetooth: pairable, with and without a prompting agent
    mkdir -p "$TMPDIR/bt/hci0"
    systemctl() { case "$*" in *--user*) return 1 ;; esac; return 0; }
    bluetoothctl() { case "$1" in list) echo 'Controller AA:BB Default' ;; show) echo '	Pairable: yes' ;; esac; }
    pgrep() { [ "$2" = "$agent_running" ]; }
    agent_running=blueman-applet
    source "$TMPDIR/bluetooth.sh" > "$TMPDIR/blueman.log"
    has blueman 'NOTE: adapter is pairable: blueman-applet holds a prompting agent'
    hasnot blueman 'BAD: adapter is pairable'
    agent_running=none
    source "$TMPDIR/bluetooth.sh" > "$TMPDIR/noagent.log"
    has noagent 'BAD: adapter is pairable with no temporary agent'
    hasnot noagent 'holds a prompting agent'
    echo 'a pairable adapter is a note under a known agent and a failure without one'
    touch $out
  ''
