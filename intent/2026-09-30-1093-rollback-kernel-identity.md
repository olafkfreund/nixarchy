---
status: draft
issue: 1093
author: olafkfreund
---

# Intent: Warn when rollback changes the booted kernel identity

## Problem

`nixarchy-rollback` compares the selected generation's `kernelVersion` with a shortened `uname -r` value before switching (`pkgs/omarchy/nix-bin/nixarchy-rollback:119-133`). A kernel rebuilt at the same version passes that comparison, so the command omits its reboot warning even though the selected kernel differs from the one booted. This part of the issue holds up. The existing `omarchy-update-restart` patch compares the resolved `/run/booted-system/kernel` and selected system kernel paths (`pkgs/omarchy/default.nix:733-745`).

The issue's NVIDIA example is broader than that fix: changing only an NVIDIA module while retaining the same kernel store path would also pass a kernel-identity comparison. This intent does not claim that kernel identity detects module-only changes.

## Proposed outcome

Rollback warns before activation when the selected generation's kernel store identity differs from the booted kernel, including same-version rebuilds. The warning leaves the user able to choose the boot menu or continue and reboot promptly.

## Affected users and systems

Users choosing an older NixOS generation through `nixarchy rollback`, especially machines with out-of-tree graphics modules. The rollback command is shipped from `pkgs/omarchy/nix-bin/`; no host-specific configuration changes are expected.

## Constraints

- Compare the booted kernel with the selected generation before changing the profile or activating it; the current system may differ from what was booted.
- Keep `--list`, generation selection, confirmation, and rollback behavior intact.
- Add a check that fails when the same-version kernel identities differ and the warning is absent; prove its red and green results under the repository's check rule.
- No changes to the criticals PR's files, including `tests/options.nix`. That file contains the existing rollback fixture at lines 3904-3928, so add a separate cheap check or sequence a change there after the criticals PR merges.

## Open questions

- Should this issue also detect a module-only rebuild with an unchanged kernel path? **Recommended: no.** Kernel identity solves the verified same-version kernel bug; module closure detection is a separate decision and needs its own evidence and check.
- What should happen if either kernel path cannot be resolved? **Recommended: show a conservative reboot warning** rather than silently treating the kernels as identical.
