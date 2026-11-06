---
status: draft
issue: 1647
author: x
---

# Intent: The published offline ISO goes

## Problem

Each release publishes an offline ISO of about 7 GB, split into four parts because it is over GitHub's asset limit, beside a network ISO of about 2 GB. The owner's judgement, 2026-11-06: it is too big and nobody uses it. Downloads back that up: rc3's offline parts have 1 download each and its network image 7. rc2's offline parts have 9 to 11, and its network image 4.

What it costs:

- The nightly's `install-iso` job: 25 minutes last night, and that job also builds and checks the network image.
- The release job's build, split, checksum and upload of four parts.
- `checks.install-iso`, `tests/install-iso.nix` (517 lines), and the offline half of `iso-budget`.
- The README's reassembly instructions, and `#try`'s offline default.

## Proposed outcome

- A release publishes one image, the network ISO. `#iso` is gone from the flake's packages and from `nixosConfigurations`.
- The nightly no longer builds or boots it. `install-iso-net` stays, and `iso-budget` measures the network image.
- The README, manual and site say one image, and that it needs a network.
- `#try` boots the network image.
- A person holding an old offline ISO is not affected. Published releases stay as they are.

## Affected users and systems

- New installers: they need a network, which is already true of everyone who picks the 2 GB image.
- A machine with no network at all, and Wi-Fi the live kernel cannot drive, can no longer install from a published image. This is the real loss, and the release note says so.
- CI and release: less to build, and no 7 GB upload.
- **#1619:** its keyboard gate refuses a non-US layout on the offline image with no network. See the open question.
- **The stock-ISO idea (#1646)** is separate and later. Nothing here depends on it.

## Constraints

- Must not break `checks.install`, `free-space`, `installer-refusal`, or `install-iso-net`.
- A list that names the image needs updating with it, and a stale one is a failure with no red (§4): `release.yml`, `nightly.yml`'s `needs`, `generated-checks.sh`, the README, `docs/`, the issue template, `docs/llms.txt`.
- A changed default a user might rely on is announced (§14).
- `v4.5.0-1` is not tagged until this lands, so that release does not publish a 7 GB image.

## Open questions

**1. Does `nixarchy reinstall iso` keep its offline image?** This is the one decision that sets the size of the job.

`nixarchy reinstall iso` builds a personal image on the person's own machine, from their configuration, with their system on it, using the same `offline` machinery in `installer/cd.nix`. `docs/manual/reinstall-image.md` calls it the only way back that survives losing the disk. It is never published, so it costs no download, and `reinstall-vm` tests it in the nightly. `--net` already exists as the smaller variant.

- **A, recommended: remove only the published image.** Keep the `offline` parameter and the installer's offline branch for the personal image. It removes everything listed above. It does not remove `cd.nix`'s offline half or the installer's offline branches, so #1619's gate stays as it is and keeps being tested by `reinstall-vm`.
- **B: remove the offline machinery entirely.** `nixarchy reinstall iso` becomes `--net` only, which fetches the system from caches at reinstall time, so a personal package no cache holds cannot come back. It removes about 200 more lines of `cd.nix`, the baked-closure branches in `install.sh`, and #1619's gate. It changes what a recovery feature promises.

**2. Does the image's name change?** With one image, `#iso-net` and its marker are misnamed. *Recommend not now:* a rename touches the installer's marker and every doc for no saving. If #1646 goes ahead, it changes this anyway.
