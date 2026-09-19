---
status: approved
issue: 788
intent: intent/2026-09-19-788-cache-box-test-image.md
---

# Spec: Cache the shared Arch box test image

## Design

Move flake.nix's existing boxImagePins table to the outer let without changing
its contents. Construct images once per system alongside it. Export the Arch
derivation as packages.<system>.box-test-image. Pass that image to box-boot
and the shared image map to box-template; retain their existing assertions.

Add .#box-test-image to cache-allowlist.sh's system group with the explicit
Docker Hub availability reason. Extend build.yml's existing early hypr-rdp
build command to build the image too, before the system cache push. Otherwise
a cold main run tries to publish an image it has not built. Keep main-only
publication and the 2048 MiB budget unchanged. Debian remains pinned and
shared but is outside this Arch-image incident's cache expansion.

Add a case to existing tests/cache-budget.nix proving the system allowlist
names the image. Validate original/new image output identity, and check that
both test definitions consume the common derivation. No new checks/workflows.

This mirrors the unmodified official Arch base image, preserving embedded
licences. Its build repository is GPL-3.0 and documents the base package set;
do not extend the public cache to proprietary app images. Account the complete
image NAR, not only its compressed download size.

## Alternatives rejected

Retrying Docker Hub leaves CI dependent on the outage duration. Adding only
an allowlist entry fails on cold stores before the image's build step.
Changing image digests or container behavior is unnecessary.

## Risks

The image adds cache cost; the existing budget must pass without raising it.
The public cache cannot serve a newly allowlisted image until main publishes
it. Distinguish a local isolated-cache proof from confirmed Cachix publication.
Avoid deleting host store paths: use disposable stores under /mnt/data/vmtest
for blocked-upstream cold substitution checks. Heavy tests require the team slot.

## Verification

Prove the allowlist assertion fails before the entry and passes after it;
remove the entry again to verify the check detects regression. Compare old
and new image output paths in the same tree. Run cache-budget and box-template
checks, then box-boot when capacity permits. Run the actual budget script and
report incremental image NAR cost. Demonstrate an isolated cold store fails
with no image/substituter and unavailable upstream, then succeeds by importing
the same image from a binary cache without contacting Docker Hub. Public
Cachix availability after main publication remains a separately reported gate.

Approval source: the user's explicit blanket approval of all #788 artifact
stages and implementation, conveyed in this task; no additional prompt required.
