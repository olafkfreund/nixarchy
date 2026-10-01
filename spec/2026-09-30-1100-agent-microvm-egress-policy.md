---
status: approved
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
   [options.nix:408-412](https://github.com/microvm-nix/microvm.nix/blob/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c/nixos-modules/microvm/options.nix#L408-L412)
   and passes it as `readonly=true` to QEMU's 9p `-fsdev` in
   [qemu.nix:291-300](https://github.com/microvm-nix/microvm.nix/blob/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c/lib/runners/qemu.nix#L291-L300).
   Also add `fileSystems."/mnt/agent-policy".options = [ "ro" ]` in the guest:
   the pinned [mounts.nix:117-131](https://github.com/microvm-nix/microvm.nix/blob/fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c/nixos-modules/microvm/mounts.nix#L117-L131)
   does not derive a guest `ro` mount option from share `readOnly`.
   Keep `modules/microvm/guest.nix:27-50`'s writable `/mnt/host` share for
   work files, and leave every other template's shares unchanged. Retain
   `dev` without `wheel` (`agent.nix:108-110`): guest root can bypass the
   guest egress filter, so the policy protection is for the unprivileged
   agent process.
2. Make the `nixarchy-agent-allowlist` unit read
   `/mnt/agent-policy/allow-hosts` after the immutable
   `/etc/nixarchy-agent/allow-hosts`, and require the new mount before the
   unit starts (`modules/microvm/templates/agent.nix:112-160`). Remove the
   `/mnt/host/allow-hosts` input entirely. Keep the existing empty-filter
   first step, hostname validation, and tinyproxy ordering. An absent or
   empty host file therefore adds no hosts; `agent-claude` keeps its
   closure-side defaults (`modules/microvm/templates/agent-claude.nix:24-45`).
   If the host policy file exists but its open or read fails, catch that
   operation's status, log the path, and fail the oneshot so tinyproxy cannot
   start with an incomplete filter. Do not use `[ -r "$src" ]` as a preflight
   proof: guest root may pass that test for a host-owned 9p file that QEMU
   cannot actually open.
3. Ensure `policy/` exists next to `share/` for new and previously created
   disposable VMs, before QEMU starts (`pkgs/microvm.nix:250-257,336-345`).
   `nixarchy vm run` can create an empty directory but must never read or
   copy the old `share/allow-hosts`. The VM owner may create and edit
   `policy/allow-hosts` on the host. For declarative VMs, extend the existing
   tmpfiles setup in `modules/services/microvm.nix:224-245` to create the
   sibling policy directory before the service starts, owned by
   `microvm:kvm` with mode `0750`; the host administrator writes
   `policy/allow-hosts` as `root:root 0644`, so the QEMU `microvm` user can
   traverse and read it. Since `microvm` owns the directory, that host user
   can replace the file even though root owns the file itself; the security
   boundary is that the guest cannot write through the read-only export.
   Update the stale
   `modules/services/microvm.nix:212-213` comment: a `kvm` group member can
   write to `share/` but cannot write to `policy/` at mode `0750`.
4. Update the user contract in `docs/manual/sandboxes.md:130-150,173-184,241-262`,
   `docs/manual/ai.md:508-516`, `data/microvm-templates.nix:85-98`, and
   the stale comments in `modules/microvm/templates/agent.nix:39-54` and
   `modules/microvm/templates/agent-claude.nix:24-27`: examples write to
   `<vm dir>/policy/allow-hosts`; the guest cannot edit this file; the
   writable `share/` still carries work files. Explain that old
   `share/allow-hosts` is ignored, and users must inspect it and copy only
   wanted entries to the new host-side location. Never migrate it
   automatically. State the declarative location under
   `/var/lib/microvms/<name>/policy/allow-hosts`, say an ordinary host user
   needs root privileges to maintain it, and retain the existing caveat
   that an allowed host remains an egress route.

## Alternatives rejected

- **Make the old file read-only inside `/mnt/host`:** That share remains
  writable, so a guest can reach the same host path through it regardless of
  a second read-only mount.
- **Rely on guest file ownership alone:** With the old writable 9p source,
  guest permissions do not protect host policy. `dev` losing `wheel` remains
  a prerequisite for the guest egress filter, not an alternative to this
  fix; guest root could flush the nftables ruleset.
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
- A declarative machine's `microvm:kvm 0750` policy directory is host-managed;
  the `microvm` host user can replace a `root:root 0644` file in the directory
  it owns. Ordinary host users need root privileges to maintain the file.
  If host permissions make it unreadable to QEMU, the guest must log the
  actual open/read failure and leave tinyproxy stopped rather than silently
  losing allowed destinations.
- The read-only guarantee relies on QEMU's 9p export implementation. A guest
  with a QEMU or kernel escape is outside this egress-policy boundary; a
  runtime guest attempt must accompany the structural check.

## Verification

- Extend `tests/microvm-template.nix:98-113,225-313,358-421` to inspect the
  built `agent` and `agent-claude` QEMU runners for a separate
  `path=policy,...,readonly=true` export, assert it does not alias
  `path=share`, and inspect the built allowlist unit for the new source and
  mount dependency, guest `ro` mount option, and no old source. Run the real
  `nixarchy-vm` against its existing stub runner to check `policy/` exists
  after create and when a pre-existing VM first runs, while a legacy
  `share/allow-hosts` is left untouched and unused.
- Extend the evaluated declarative-machine coverage in `tests/options.nix:2507-2522`
  to assert the policy tmpfiles directory is `microvm:kvm 0750` alongside
  `share/`. Run this check in CI; it is too large for the local gate.
- In `tests/microvm-boot.nix:98-127` or a focused guest test, prove that
  unprivileged `dev` cannot modify or replace
  `/mnt/agent-policy/allow-hosts` (including through `/mnt/host`), while a
  host edit is read after a guest restart and the old writable file is
  ignored. Test an unreadable host file and assert a clear diagnostic in the
  guest journal with no widened allowlist. Run only in CI; no local VM run.
- Break-prove the structural check during implementation: copy
  `modules/microvm/templates/agent.nix` aside outside the worktree, remove
  `readOnly = true`, confirm the `microvm-template` check fails with the
  writable-policy assertion, restore the file with `cp`, and confirm green.
  Similarly remove the guest `ro` mount option and watch its assertion fail.
  Repeat by restoring `/mnt/host/allow-hosts` as the unit source: the check
  must fail on the stale-source assertion before being restored and passing.
  Capture the red outputs for the PR. Never use `git checkout` as a restore
  shortcut.
