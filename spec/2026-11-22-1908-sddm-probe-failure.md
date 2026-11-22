---
status: approved
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

    verdict=$(awk 'NF == 0 { next } NF < 4 || $2 !~ /^[0-9]+$/ || $4 !~ /^(seat|-$)/ { bad = 1 } $4 ~ /^seat/ { seat = 1 }
      END { print (bad ? "unreadable" : seat ? "seated" : "seatless") }' <<<"$sessions") || exit 0
    [ "$verdict" = seatless ] || exit 0

- awk exits non-zero: `|| exit 0`, no restart.
- A non-blank line with fewer than four fields, a non-numeric UID, or a fourth
  field that is neither `seat…` nor `-`: `unreadable`, no restart. That last
  rule catches a lost or moved SEAT column.
- Any line with a `seat*` fourth field: `seated`, no restart.
- Only well-formed lines and none on a seat, or no lines at all: `seatless`,
  restart, as upstream.

`checks.sddm-recover` gains a stub awk on PATH that exits 2 when asked to (else
execs gawk), and four cases: unparseable `loginctl` output (an error line), a
failing awk with a seatless list (so a bypassed stub would restart and go red),
and a row with no seat column, each wanting zero restarts; and an empty list,
wanting one, which keeps upstream's behaviour from regressing.

`checks.session`'s probe runs the same verdict program on the guest's real
`loginctl` output and requires `seated` before it runs the hook, so the hook's
no-restart there comes from a seat, not from an unreadable list.

## Alternatives rejected

- `loginctl list-sessions -o json` with jq: changes which tool decides and how a
  seatless session is spelled; a larger divergence from upstream's script to
  carry for the same outcome.
- Filing upstream: the owner said not to.

## Risks

A column inserted before SEAT whose values are `-` would still read as
`seatless`. systemd older than 254 printed an empty seat as blanks, so a seatless
row could drop to three fields and read as `unreadable`, suppressing a real
restart; nixarchy's systemd is newer. The verdict program is copied into
`checks.session`, so a change to one must be made to both.

## Verification

Red: the two new zero-restart cases fail against #1905's patch (restarts 1).
Green with the patch. Generated checks under the carry pin, main's tag and the
efcf615 fallback; `session` on the carry, which runs the hook as systemd runs it
against real loginctl output while the greeter holds seat0.
