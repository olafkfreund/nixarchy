---
status: draft
issue: 1100
intent: intent/2026-09-30-1100-agent-microvm-egress-policy.md
---

# Spec: Put agent MicroVM egress policy in a read-only host share

## Design

1. In `modules/microvm/templates/agent.nix:39-54,112-163`, add one
   agent-only 9p share: `source = "policy"`, a distinct tag and mount point
   `/mnt/agent-policy`, and `readOnly = true`. The source is a `policy/`
   sibling of the existing writable `share/`, never a child of it. The pinned
   microvm.nix revision in `flake.lock:592-610` defines share `readOnly` in
   [options.nix:387-391](https://github.com/microvm-nix/microvm.nix/blob/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c/nixos-modules/microvm/options.nix#L387-L391)
   and passes it as `readonly=true` to QEMU's 9p `-fsdev` in
   [qemu.nix:291-300](https://github.com/microvm-nix/microvm.nix/blob/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c/lib/runners/qemu.nix#L291-L300).
   Keep `modules/microvm/guest.nix:27-50`'s writable `/mnt/host` share for
   work files, and leave every other template's shares unchanged.
2. Make the `nixarchy-agent-allowlist` unit read
   `/mnt/agent-policy/allow-hosts` after the immutable
   `/etc/nixarchy-agent/allow-hosts`, and require the new mount before the
   unit starts (`modules/microvm/templates/agent.nix:112-160`). Remove the
   `/mnt/host/allow-hosts` input entirely. Keep the existing empty-filter
   first step, hostname validation, and tinyproxy ordering. An absent or
   empty host file therefore adds no hosts; `agent-claude` keeps its
   closure-side defaults (`modules/microvm/templates/agent-claude.nix:24-45`).
3. Ensure `policy/` exists next to `share/` for new and previously created
   disposable VMs, before QEMU starts (`pkgs/microvm.nix:250-257,336-345`).
   `nixarchy vm run` can create an empty directory but must never read or
   copy the old `share/allow-hosts`. The VM owner may create and edit
   `policy/allow-hosts` on the host. For declarative VMs, extend the existing
   tmpfiles setup in `modules/services/microvm.nix:224-245` to create the
   sibling policy directory before the service starts, owned by
   `microvm:kvm` with mode `0750`; the host administrator writes its file.
   The guest sees this directory only through its read-only export.
4. Update the user contract in `docs/manual/sandboxes.md:130-150,173-184,241-262`
   and `data/microvm-templates.nix:85-98`: examples write to
   `<vm dir>/policy/allow-hosts`; the guest cannot edit this file; the
   writable `share/` still carries work files. Explain that old
   `share/allow-hosts` is ignored, and users must inspect it and copy only
   wanted entries to the new host-side location. Never migrate it
   automatically. State the declarative location under
   `/var/lib/microvms/<name>/policy/allow-hosts` and retain the existing
   caveat that an allowed host remains an egress route.

## Alternatives rejected

- **Make the old file read-only inside `/mnt/host`:** That share remains
  writable, so a guest can reach the same host path through it regardless of
  a second read-only mount.
- **Trust guest ownership or `dev` losing `wheel`:** The allowlist input is a
  writable 9p export; `modules/microvm/templates/agent.nix:108-110` already
  removes `wheel` and the bug remains.
- **Copy the old file automatically:** A guest may already have added hosts
  there. Copying it would preserve the widened policy.
- **QEMU `-fw_cfg` or kernel-command-line injection:** Both require new
  per-VM argument transport and guest parsing. The pinned 9p share option
  already provides a read-only per-VM file path.

## Risks

- Existing agents that relied on `share/allow-hosts` will lose those extra
  destinations until their owner copies approved entries to `policy/`. The
  proxy still denies absent hosts; `agent-claude` retains its baked defaults.
- A missing `policy/` directory can prevent QEMU from starting even when no
  allowlist file is intended. Create it in both runner paths and cover an
  existing disposable VM, not just `nixarchy vm create`.
- A declarative machine's `microvm:kvm` policy directory is host-managed,
  not editable by an ordinary guest. The host administrator may need elevated
  privileges to place `allow-hosts` there.
- The read-only guarantee relies on QEMU's 9p export implementation. A guest
  with a QEMU or kernel escape is outside this egress-policy boundary; a
  runtime guest attempt must accompany the structural check.

## Verification

- Extend `tests/microvm-template.nix:98-113,225-313,358-421` to inspect the
  built `agent` and `agent-claude` QEMU runners for a separate
  `path=policy,...,readonly=true` export, assert it does not alias
  `path=share`, and inspect the built allowlist unit for the new source and
  mount dependency with no old source. Run the real `nixarchy-vm` against its
  existing stub runner to check `policy/` exists after create and when a
  pre-existing VM first runs, while a legacy `share/allow-hosts` is left
  untouched and unused.
- Extend the evaluated declarative-machine coverage in `tests/options.nix:2507-2522`
  to assert the policy tmpfiles directory is `microvm:kvm 0750` alongside
  `share/`. Run this check in CI; it is too large for the local gate.
- In `tests/microvm-boot.nix:98-127` or a focused guest test, prove that
  `dev` cannot modify or replace `/mnt/agent-policy/allow-hosts` (including
  through `/mnt/host`), while a host edit is read after a guest restart and
  the old writable file is ignored. Run only in CI; no local VM run.
- Break-prove the structural check during implementation: copy
  `modules/microvm/templates/agent.nix` aside outside the worktree, remove
  `readOnly = true`, confirm the `microvm-template` check fails with the
  writable-policy assertion, restore the file with `cp`, and confirm green.
  Repeat by restoring `/mnt/host/allow-hosts` as the unit source: the check
  must fail on the stale-source assertion before being restored and passing.
  Capture both red outputs for the PR. Never use `git checkout` as a restore
  shortcut.
