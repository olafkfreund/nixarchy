---
status: draft
issue: 1100
author: olafkfreund
---

# Intent: Keep an agent MicroVM's egress policy outside its writable share

## Problem

The issue's central claim holds. `modules/microvm/guest.nix:44-49` mounts the
per-VM `share/` at `/mnt/host`, and
`modules/microvm/templates/agent.nix:112-163` reads
`/mnt/host/allow-hosts` at boot to build tinyproxy's allow filter. Nothing
prevents the guest's `dev` user from changing that file through the writable
share. A newly added hostname therefore becomes permitted after the next boot,
despite `dev` losing `wheel` in `agent.nix:108-110`. The existing
`tests/microvm-template.nix:306-313` checks where the filter is written, not
whether the guest can change its source.

The issue's ownership explanation needs qualification. Disposable VMs use a
share created under the invoking user's state directory
(`pkgs/microvm.nix:250-257`), whereas declarative VMs use a host share owned
by `microvm:kvm` (`modules/services/microvm.nix:224-243`). The shared 9p
configuration defaults to `security_model=none`; matching guest and host UID
1000 is not a prerequisite for the unsafe policy path. The issue reports an
inference from code, not a reproduced guest write; runtime proof is still
needed.

## Proposed outcome

An agent guest cannot add, replace, or delete the per-VM egress allowlist,
including across a restart. A host user or administrator can still maintain
that list per VM without rebuilding the shared template. A missing policy
file continues to deny all hosts except any closure-side defaults.

## Affected users and systems

Disposable `agent` and `agent-claude` VMs run through `nixarchy vm`, and
declarative agent VMs configured through `programs.nixarchy.services.microvm`.
The host-side runner and state setup, the guest share and allowlist unit, and
their checks are affected. Other MicroVM templates should keep their existing
writable `/mnt/host` behavior.

## Constraints

- Keep per-VM policy outside the guest-writable `share/` tree. A read-only
  mount alone is insufficient if the same host path is reachable through the
  writable share.
- Preserve the closure-side defaults in
  `/etc/nixarchy-agent/allow-hosts` and fail closed when host policy is absent.
- Cover both disposable and declarative runners; do not build a policy into a
  template closure shared by many VMs.
- Prove a guest cannot mutate the policy and that a host policy edit takes
  effect at the next boot. Break-prove any new check.
- No local builds or VM runs at this gate.

## Open questions

- **Policy transport:** Recommend a separate read-only 9p share backed by a
  host-managed `policy/` sibling of `share/`. The pinned microvm.nix share
  option supports `readOnly`, and its QEMU runner passes `readonly=true` to
  `-fsdev`; this preserves the current file and per-VM model with the fewest
  moving parts. Alternatives are QEMU `-fw_cfg` or kernel-command-line
  injection, which need new argument plumbing and parsing. Does the owner
  approve the separate share?
- **Existing files:** Recommend ignoring `share/allow-hosts` after the change
  and asking the host user to inspect and copy wanted entries to the new
  host-side policy location. Automatically copying a guest-writable file
  would carry any attacker-added hostname into the protected policy. Is that
  fail-closed migration acceptable?
