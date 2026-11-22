---
status: draft
issue: 1908
intent: intent/2026-11-22-1908-sddm-probe-failure.md
---

# Spec: the after-sleep SDDM recovery restarts only on a probe that read no seat

## Design

`pkgs/omarchy/quattro-script-ports.sh` already patches
`bin/omarchy-system-sddm-recover` where a pin ships it (#1905). A third
`--replace-fail` swaps upstream's

    if awk '$4 ~ /^seat/ { found=1; exit } END { exit !found }' <<<"$sessions"; then
      exit 0
    fi

for an awk that prints a verdict and a test of it:

    verdict=$(awk 'NF == 0 { next } NF < 4 || $2 !~ /^[0-9]+$/ { bad = 1 } $4 ~ /^seat/ { seat = 1 }
      END { print (bad ? "unreadable" : seat ? "seated" : "seatless") }' <<<"$sessions") || exit 0
    [ "$verdict" = seatless ] || exit 0

- awk exits non-zero: `|| exit 0`, no restart.
- A non-blank line with fewer than four fields, or a non-numeric UID: `unreadable`,
  no restart.
- Any line with a `seat*` fourth field: `seated`, no restart.
- Only well-formed lines and none on a seat, or no lines at all: `seatless`,
  restart, as upstream.

`checks.sddm-recover` gains a stub awk on PATH that exits 2 when asked to (else
execs gawk), and three cases: unparseable `loginctl` output (an error line),
a failing awk with a seated list, both wanting zero restarts; and an empty list,
wanting one, which keeps upstream's behaviour from regressing.

## Alternatives rejected

- `loginctl list-sessions -o json` with jq: changes which tool decides and how a
  seatless session is spelled; a larger divergence from upstream's script to
  carry for the same outcome.
- Filing upstream: the owner said not to.

## Risks

Output that keeps four fields and a numeric second field but moves the seat out
of column four would still read as `seatless`; the old probe had the same hole,
and the session probe in `checks.session` runs the real loginctl.

## Verification

Red: the two new zero-restart cases fail against #1905's patch (restarts 1).
Green with the patch. Generated checks under the carry pin, main's tag and the
efcf615 fallback; `session` on the carry, which runs the hook after a real sleep
target.
