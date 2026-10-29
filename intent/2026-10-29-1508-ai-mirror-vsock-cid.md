---
status: draft
issue: 1508
author: x
---

# Intent: hyprland-ai-mirror gets a vsock CID per VM, and a check

## Problem

The `hyprland-ai-mirror` template (#1504, #1505) sets
`microvm.vsock.cid = 1504`. The runner is one closure per template, so every
VM made from it asks qemu for CID 1504, and a second one fails to start. The
template's note and `docs/manual/sandboxes.md` both say "one at a time"
because of this.

The template also has no check. It and `checks.microvm-template` are the only
things that build it, and the latter only reads runner shape. The autoconfirm
loop and the listener's wiring are covered by nothing that runs on a pull
request.

## Proposed outcome

- Any number of `hyprland-ai-mirror` VMs run at once, each on its own CID.
- The CID is stable for a VM's life, so its MCP registration stays valid
  across restarts.
- The connect line in the note and the manual reads the CID from the VM's
  directory instead of the fixed `1504`, and "one at a time" goes.
- `checks.microvm-ai-mirror`, a cheap `runCommand` that boots nothing, covers
  the CID script, the autoconfirm loop against a stub and the guest wiring.
  It is shown failing when each part is broken.

## Affected users and systems

- `modules/microvm/templates/hyprland-ai-mirror.nix`, a new CID script beside
  it, `data/microvm-templates.nix` (the note), `docs/manual/sandboxes.md`,
  a new `tests/microvm-ai-mirror.nix` and its `flake.nix` registration, and
  `tests/AGENTS.md`.
- Users of the template. Their MCP registration changes from `…:1504:7000`
  to the per-VM CID. Anyone already registered re-adds it once.

## Constraints

- One closure per template: the CID must not be compiled in. It is chosen at
  run time through `microvm.extraArgsScript`, which `microvm-run` executes
  from the VM's directory. This was measured on the scratch branch
  `feat/1504-hyprland-ai-mirror`: two VMs ran at once, each answered MCP and
  drove its own desktop, and vsock also works on the `-tcg` runner.
- The CID file sits beside `share/`, never in it, so the guest cannot choose
  its own CID.
- The template's behaviour stays as merged: port 7000, socat listener,
  autoconfirm. Only the CID and the docs change.
- The security note in the manual (any local user can connect) stays and
  stays true.

## Open questions

1. A declared machine (`programs.nixarchy.services.microvm`) runs the same
   runner from `/var/lib/microvms/<name>`. Should the docs name that path,
   or only the `nixarchy vm` one? Default: name both, one line.
