---
status: draft
issue: 1516
author: x
---

# Intent: nixarchy-desktop powers off on `nixarchy vm stop`, and a check sees it

## Problem

`nixarchy vm stop` on a `nixarchy-desktop` VM never returns. `microvm-shutdown`
sends QMP `system_powerdown`, an ACPI power-button press. The template imports
the full nixarchy module, which sets
`services.logind.settings.Login.HandlePowerKey = lib.mkDefault "ignore"`
(`modules/nixos.nix`) so the key opens Omarchy's power menu. In the VM nobody
answers that menu, so qemu keeps running (measured 3+ minutes; SIGTERM was the
workaround).

PR #1517 sets `"poweroff"` in the template, but its `lint` job fails: statix
counts three top-level `services.` keys in the file. And no check would notice
the bug coming back (CLAUDE.md §2).

## Proposed outcome

- `nixarchy vm stop` on `nixarchy-desktop` shuts the guest down and returns.
- The host desktop is unchanged: its power key still opens the Omarchy menu.
- `checks.microvm-template` fails if the built guest's `logind.conf` does not
  say `HandlePowerKey=poweroff`, shown failing with the line removed.
- #1517 goes green and merges, closing #1516.

## Affected users and systems

- `modules/microvm/templates/nixarchy-desktop.nix` (merge `services.` keys,
  add the override) and `tests/microvm-template.nix` (one closure assertion).
- Users of the `nixarchy-desktop` template. No other template imports the
  nixarchy module (`data/microvm-templates.nix` names it the only exception),
  so no other template has the bug.

## Constraints

- Plain priority, not `mkForce` (CLAUDE.md §7): it beats the `mkDefault`.
- The probe reads the built guest closure, the way the file's agent checks
  already do, so it adds no NixOS evaluation. The check needs the runners,
  which CI builds anyway; locally it is VM-tier only if the runner is not
  already in the store, and runs only with CI idle (§6).

## Reviews

agy (model not reported) and codex (gpt-6-sol) reviewed it read-only. They
agree on the fix and the statix cause. They split on the probe: codex would
evaluate the template in `checks.microvm-ai-mirror` (one more full nixarchy +
Home Manager evaluation in a cheap check); agy would read the built
`logind.conf` in `checks.microvm-template` (no extra evaluation, tests the
rendered file). This intent takes agy's.

## Open questions

None.
