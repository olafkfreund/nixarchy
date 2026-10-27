---
status: approved
issue: 1462
author: x
---

# Intent: remove hypr-rdp

## Problem

hypr-rdp, the RDP server under `programs.nixarchy.services.hypr-rdp`, has no
users. gliff, installed by default, covers remote desktop between nixarchy
machines, and Omarchy's own path is the better one.

It still costs CI on every nixpkgs bump: 447 Rust crates, 5.5 to 11 minutes
cold (#738, #1030), plus its checks, docs and a vendored patch.

## Proposed outcome

hypr-rdp is gone: the module, the package, the flake input, the overlay, the
checks, the cache entry, the CI step, `nixarchy-remote` and the manual's RDP
sections.

- A configuration that still sets the option is told, at rebuild, that it was
  removed and what to use instead.
- sops-nix stays, and keeps a check that forces `sops-install-secrets`.
- The freerdp client stays in the app catalogue.

## Affected users and systems

- Anyone who set `programs.nixarchy.services.hypr-rdp.*`: the rebuild fails
  with the removal message. Nobody is known to have set it.
- CI loses its slowest cold build.
- #1459's pin-fix probe for sops-nix moves to the new check.

## Constraints

- **Mode A is untouched:** the removal line adds nothing to a machine that
  never set the option.
- **The docs check and the release notes stay honest.** `checks.doc-options`
  must not treat the hidden removed option as approving stale paths, and the
  release notes must not list it as new.
- **Every touched check is shown to fail (§1).**

## Open questions

None. The owner decided this on 2026-10-26.
