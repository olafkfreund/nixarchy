---
status: approved
issue: 1381
author: olafkfreund
---

# Intent: the nightly nixpkgs bump merges when nothing it changes is broken

## Problem

The nightly nixpkgs bump, PR #1378 (nixpkgs 09063bd: 10 app versions, and
Qt 6.11.2 → 6.12.0), is red, and none of its three failures says anything
is wrong with the apps it moves:

1. **`checks.copilot-handoff` is flaky by construction.** Its negative
   control restores `head -100` in a copy of
   `.github/scripts/copilot-handoff.sh`, and expects that copy to die of
   SIGPIPE when fed the stub's 500-line log
   (`tests/copilot-handoff/gh`, `tests/copilot-handoff.nix` ~55-75).
   Whether `head` closes the pipe while the upstream stage is still
   writing depends on pipe buffering and scheduling, and 500 short lines
   (~30 KB) fit in a 64 KiB pipe. On #1378's run the control passed, so
   the check failed with its own message: "500 lines no longer reproduces
   the SIGPIPE on this machine". The thing it guards (#1157) did not
   regress.
2. **`checks.session` caught a real regression, in a plugin.** Under Qt
   6.12 the nixi plugin logs QML TypeErrors (`HarnessSelector.qml`,
   `Ask.qml`: `Cannot read property 'text' / 'border' / 'r' of
   undefined`, `Unable to assign [undefined] to QColor`). The session
   check asserts that the shell logs no QML type errors, and fails.
   `main`'s last green session log has none of these, and Quickshell is
   0.3.2 in both. This is the assertion working: on 6.12 a nixarchy user
   would get a nixi panel with missing colours.
3. **A kernel-modules collision.** `checks.offline-hardware-packages`
   builds a system whose module tree bundles VirtualBox-GuestAdditions
   7.2.20 with linux 7.2.11-modules, and both ship
   `lib/modules/7.2.11/modules.builtin.alias.bin`. The buildEnv refuses
   it. That is a nixpkgs packaging change inside the bump.

Until all three are resolved, nothing from nixpkgs reaches users, and the
daily bump keeps reopening red.

## Proposed outcome

- `copilot-handoff`'s control fails deterministically against the
  `head -100` bug on any machine. The check still fails the bug and
  passes the fix (§1), and stops depending on timing.
- nixi renders without QML errors on Qt 6.12, and also on 6.11, so a
  `main` that has not taken the bump keeps working. The fix lands in
  nixi's own repository (`olafkfreund/nixi`, also maintained here), with
  its pin moved in `flake.nix`. The `session` assertion is not weakened
  or given an exception.
- The offline hardware set builds on the new nixpkgs. Either guest
  additions stop shipping a file the kernel already ships, by the
  smallest override, or nixpkgs has already fixed it and the bump takes
  that.
- The bump PR (#1378, or the next night's) goes green and merges.

## Affected users and systems

- Everyone, through the nixpkgs pin: these fixes gate every app and
  security update in the bump.
- nixi users: every default install, since nixi is a default plugin.
- Machines that install offline with VirtualBox guest additions in the
  hardware set.
- Files: `tests/copilot-handoff/gh` and `tests/copilot-handoff.nix`; the
  nixi repository and its `flake.nix` pin; wherever the offline hardware
  set adds guest additions.

## Constraints

- **Do not weaken any assertion.** The QML-errors rule is what found a
  user-visible break. The fix is in nixi, not in the check.
- **Each fix is independent.** Ship them as separate commits, or separate
  PRs if one lands faster, so one does not hold the others.
- **§1 for `copilot-handoff`:** the new control must fail against
  `head -100`, and its break must be shown to have landed, on a
  machine where the old 500-line control passed, which is today's CI
  runner and possibly p620.
- **§3:** the nixi fix is proved on Qt 6.12 (red before, green after),
  and on 6.11 (green).
- Posting to nixpkgs upstream about the collision needs your approval
  (§11).

## Open questions

- **One PR or three?** I propose one issue with three PRs, because they
  touch unrelated files and have different review costs. A nixi pin bump
  with its session proof is heavier than a test stub. Each PR says
  `Refs #1381`, and the last one closes it.
- **Retarget #1378 or let the bot reopen?** I propose letting the next
  nightly bump run open a fresh PR once the fixes are on `main`, rather
  than hand-editing the bot's branch.
