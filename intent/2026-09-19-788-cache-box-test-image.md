---
status: draft
issue: 788
author: olafkfreund
---

# Intent: Keep the box test image available during Docker Hub outages

## Problem

Cold runners fetch the pinned Arch image from Docker Hub because it is absent
from the public cache allowlist. A registry HTTP 502 failed main's box check.
The digest table is already shared; the tests independently construct its
image derivation and no named package lets the cache publish it.

## Proposed outcome

Both box checks consume one named Arch image output. The existing main-only
cache path builds and publishes it, and cold stores can substitute it when
Docker Hub is unavailable. Its cost remains inside the existing 2 GiB budget.

## Affected users and systems

Cold CI runners, box checks and nixarchy.cachix.org. No desktop deployment.

## Constraints

Preserve image digests/hashes, public-cache licensing restrictions and the
budget. Never delete images from the host store to simulate cold conditions.
Coordinate heavy builds and CI pushes with the team. This is an explicit
availability exception to the usual exclusion of prebuilt downloads.

## Open questions

None. The user explicitly authorized all artifact stages and implementation
for #788 without further approval prompts; record approval commits separately.
