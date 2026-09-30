---
status: approved
issue: 1096
intent: intent/2026-09-30-1096-nonfailing-checks.md
---

# Spec: Make four checks fail when their protected behavior breaks

## Design

1. In `tests/installer-network.nix:150-158`, extract `connect_wifi()` from `installer/install.sh:347-470`, require a nonempty extraction, and assert its executable missing-interface guard. The existing whole-script grep can be satisfied by `ask_network()` (`installer/install.sh:498-536`); a bare `phy80211` grep of `connect_wifi()` would still match its explanatory comment at lines 385-387. Match the conditional command, not that word alone. Keep the check scoped to the no-networks branch so an unrelated use cannot satisfy it.
2. In `tests/dashboard-clock.nix:55-107`, stop discarding `script -qec` failures. Each skew and the empty-tips case must exit successfully and produce the stable `Installing nixarchy` frame emitted by `ui_dashboard_draw()` at `installer/lib/dashboard.sh:90`. Preserve the existing negative matches for sed and arithmetic errors as useful diagnostics. `ui_dashboard_tick()` at `installer/lib/dashboard.sh:118-160` is the function under test.
3. In `tests/shell-ipc-resolve.nix:86-93`, delete the no-op assertion at line 89. Initialize `argv.two2` before the two-instance invocation and assert that no `-i` selection or other non-probe IPC call was sent. Keep the refusal-text and instance-name assertions and the new slow-probe case added by #1092 at `tests/shell-ipc-resolve.nix:107-113`. The product's multi-instance refusal is in `pkgs/omarchy/default.nix:2055-2060`.
4. In `tests/installer-failure-hints.nix:114-125`, require `printed.sh` to be nonempty before the negative wording match. Keep comment stripping: comments in `installer/install.sh:440-442` contain wording that the executable `ui_left` at line 443 correctly avoids. This establishes that the negative match examined at least one printed line; the existing exit-code mapping assertions remain.

All four are amendments to registered checks in `flake.nix:1774,1931-1948,2315`, with no new check or workflow registration. No production behavior change is proposed.

## Alternatives rejected

- Grep the entire installer or a function for `phy80211`: another function and a comment already carry the token, so the check could still pass with the guard gone.
- Match only an absence of error text in the dashboard output: a command that never draws a frame can satisfy it.
- Search a producer pipe with `grep -q`: `pipefail` can report SIGPIPE after a successful match; use files or captured strings.
- Alter `.github/workflows` to solve an assertion gap: these checks are already registered and run; any later CI-gate change belongs to a human under root `AGENTS.md` §11.

## Risks

- These are narrow static or stubbed checks. They cannot prove a real wireless radio, live dashboard terminal, or shell instance works; the check names should continue to describe those limits.
- An exact shell-line match can fail after a harmless refactor. Match the executable conditional in the correct branch, with a failure message showing the extracted text, and update the check when behavior moves.
- The criticals PR merged as #1111 before this revision. It moved the relevant `installer/install.sh` lines without changing the `connect_wifi()` guard or the four blind assertions. Separately, #1092 added a slow-probe case to `tests/shell-ipc-resolve.nix`; the case 3 gap remains. Preserve that new coverage. The spec has returned to draft for approval against current main.

## Verification

After this revised spec and the plan are separately approved, use a copy-aside/restore cycle for each break; never use `git checkout` to restore a staged test file. Build only the affected cheap check for each break and capture its failing line, then restore the product or fixture and show the check passing. The four breaks are:

1. Remove only the executable `if ! ls -d /sys/class/net/*/phy80211` guard from `connect_wifi()` while leaving its comment and `ask_network()` intact. `checks.installer-network` must fail on the scoped assertion.
2. Rename or remove `ui_dashboard_tick()` in the copied dashboard source. `checks.dashboard-clock` must fail on the `script` exit or missing frame for every skew, rather than announce clean draws.
3. Insert an unintended `qs ipc -n -i aaa111` call immediately before the existing multi-instance refusal in the carried shell patch, preserving the refusal text. `checks.shell-ipc-resolve` must fail on the recorded call, not merely on the message.
4. Remove the executable `ui_left` lines from `connect_wifi()` while keeping its exit-code arms and comments. `checks.installer-failure-hints` must fail because `printed.sh` is empty.

Run `nix fmt` after each `.nix` edit and inspect `git diff --stat`; finish with `nix fmt -- --ci`, statix and deadnix. No Nix builds, VM checks, or PR occur at this revised spec gate. The owner retains any decision to change a CI workflow.
