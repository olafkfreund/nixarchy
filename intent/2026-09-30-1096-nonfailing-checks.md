---
status: draft
issue: 1096
author: olafkfreund
---

# Intent: Make four checks fail when their protected behavior breaks

## Problem

All four findings in #1096 hold in the current tree:

- `tests/installer-network.nix:153` searches the whole installer for `phy80211`. The `ask_network()` gate already supplies that text, so removing the wireless-interface guard from `connect_wifi()` would leave this assertion green.
- `tests/dashboard-clock.nix:56-107` discards `script` failures with `|| true` and only rejects selected error messages. If `ui_dashboard_tick` is missing, `command not found` is not among them and the check can report that every skew drew clean.
- `tests/shell-ipc-resolve.nix:89` is a no-op assertion. Its two-instance case checks refusal text, but never checks the recorded `argv.two2`, so it can miss an `-i` call aimed at an arbitrary instance before refusal.
- `tests/installer-failure-hints.nix:120-125` accepts an empty `printed.sh`: the negative wording assertion passes even if no `ui_left` diagnostic remains in `connect_wifi()`.

These are gaps in the checks, not evidence that the current product behavior is broken. Passing results currently overstate what the checks prove.

## Proposed outcome

Each assertion examines the behavior it names, refuses an empty or failed observation, and has a documented break that makes it fail. The installer network check examines `connect_wifi()` itself; the dashboard check requires a successful draw; the IPC check rules out calls against either instance in the refusal case; and the failure-hints check requires at least one printed diagnostic before checking its wording.

## Affected users and systems

Contributors and reviewers rely on `checks.installer-network`, `checks.dashboard-clock`, `checks.shell-ipc-resolve`, and `checks.installer-failure-hints` to catch regressions. Users would encounter any missed installer Wi-Fi diagnostic, dashboard failure, or wrong-shell IPC command. No runtime setting changes are intended.

## Constraints

- Prove each corrected assertion red against its corresponding broken behavior and green after restoration, per root `AGENTS.md` §1. Capture the red output for the eventual PR.
- This round permits the spec only: no Nix builds, PR, or edits to the test implementations. Stay at the spec gate until the criticals PR merges.
- `tests/installer-network.nix` and `tests/installer-failure-hints.nix` are explicitly reserved for the unpushed criticals PR. Sequence their edits after it lands; do not work around the restriction by changing `installer/install.sh`.
- Keep observations cheap and scoped to the existing checks. Avoid producer pipes into `grep -q` under `pipefail` and any fixture write to `omarchy/shell.json`.
- No `.github/workflows` edit is needed for the observed gaps. Any later CI-gate change remains human-owned under root `AGENTS.md` §11.

## Open questions

- **Owner decision:** draft the spec now, then stay at the spec gate until the criticals PR merges. Change and break-prove all four checks only after that merge.
- Should a renamed or missing dashboard tick fail on exit status, a stable frame marker, or both? **Recommended:** require successful `script` exit and the always-drawn `Installing nixarchy` frame marker; preserve the specific arithmetic error checks for diagnosis.
