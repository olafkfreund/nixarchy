---
status: approved
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

## Decisions

The owner approved this on 2026-11-06, choosing option B.

**1. The offline machinery goes entirely.** Not only the published image: the `offline` parameter in `installer/cd.nix`, and the installer's baked-closure branches. `nixarchy reinstall iso` becomes network-only, so it fetches the system from caches at reinstall time, and a personal package no cache holds cannot come back. That changes what a recovery feature promises, so `docs/manual/reinstall-image.md` and the release note say so. #1619's gate, which refuses a non-US layout on an image with no network, goes with it.

**2. The image's name stays `#iso-net` for now.** A rename touches the installer's marker and every doc for no saving, and #1646 may change it anyway.
