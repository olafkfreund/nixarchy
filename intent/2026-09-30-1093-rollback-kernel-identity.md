---
status: approved
issue: 1093
author: olafkfreund
---

# Intent: Warn when rollback changes the booted kernel identity

## Problem

`nixarchy-rollback` compares the selected generation's `kernelVersion` with a shortened `uname -r` value before switching (`pkgs/omarchy/nix-bin/nixarchy-rollback:119-133`). A kernel rebuilt at the same version passes that comparison, so the command omits its reboot warning even though the selected kernel differs from the one booted. This part of the issue holds up. The existing `omarchy-update-restart` patch compares the resolved `/run/booted-system/kernel` and selected system kernel paths (`pkgs/omarchy/default.nix:733-745`).

The issue's NVIDIA example is broader than a kernel-only fix: changing only an NVIDIA module while retaining the same kernel store path would still pass a kernel-identity comparison. The selected and booted systems also expose a `kernel-modules` link, so both identities can be compared.

## Proposed outcome

Rollback warns before activation when either the selected generation's kernel or kernel-modules store identity differs from the booted system, including same-version kernel and module rebuilds. The warning leaves the user able to choose the boot menu or continue and reboot promptly.

## Affected users and systems

Users choosing an older NixOS generation through `nixarchy rollback`, especially machines with out-of-tree graphics modules. The rollback command is shipped from `pkgs/omarchy/nix-bin/`; no host-specific configuration changes are expected.

## Constraints

- Compare the booted kernel and kernel modules with the selected generation before changing the profile or activating it; the current system may differ from what was booted.
- Keep `--list`, generation selection, confirmation, and rollback behavior intact.
- Add a check that fails when the same-version kernel or module identities differ and the warning is absent; prove its red and green results under the repository's check rule.
- No changes to the criticals PR's files, including `tests/options.nix`. That file contains the existing rollback fixture at lines 3904-3928, so add a separate cheap check or sequence a change there after the criticals PR merges.

## Open questions

- **Owner answer:** compare resolved `kernel` and `kernel-modules` paths together, from `/run/booted-system` and the selected generation. This covers a module-only rebuild, including NVIDIA, when its module store identity changes but its kernel identity does not. Both links exist in this NixOS host's booted and current system trees.
- **Owner answer:** if any of the four paths cannot be resolved, show a conservative reboot warning rather than silently treating the systems as identical.
