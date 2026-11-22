---
status: draft
issue: 1908
spec: spec/2026-11-22-1908-sddm-probe-failure.md
coders:
  1: claude  # one substitution in a file already open; a handoff costs more than it saves
  2: claude  # three cases in an existing check, beside the stubs they extend
reviewers:
  - codex  # second reading of the awk verdict under set -euo pipefail
  - agy    # second reading of whether each stub can go red
---

# Plan: the after-sleep SDDM recovery restarts only on a probe that read no seat

Decisions carried from the spec: replace upstream's `if awk …` with a verdict
(`seated`, `seatless`, `unreadable`) and restart only on `seatless`; a failed
awk exits 0; blank lines are skipped so an empty list still restarts; patch
only where the pin ships the script, as #1905 does. Not filed upstream.

## Steps

1. `pkgs/omarchy/quattro-script-ports.sh`, the `omarchy-system-sddm-recover`
   block: add a third `--replace-fail` with the verdict awk. → verify by
   building `.#omarchy` and reading the built script.
   Traps: shell quoting inside a double-quoted replacement (`\$`, `\"`);
   `--replace-fail` must match upstream's three lines exactly.
2. `tests/sddm-recover.nix`: a stub awk (`AWK_FAIL=1` exits 2, else execs gawk),
   and the cases `unparseable logind output is left alone` (0),
   `a failing awk is left alone` (0), `no sessions at all restarts the display
   manager` (1). → verify by `nix build .#checks.x86_64-linux.sddm-recover`.
   Traps: §1, prove the two zero cases fail on #1905's patch first.

## Tests

- Red: step 2 on #1905's patch fails both zero-restart cases.
- All generated checks under the carry pin, main's v4.5.0 and efcf615;
  `session` on the carry.

## Rollback

Revert the two commits; the probe returns to upstream's.
