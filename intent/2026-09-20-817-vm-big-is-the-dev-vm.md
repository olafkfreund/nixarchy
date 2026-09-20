---
status: draft
issue: 817
author: olafkfreund
---

# Intent: the persistent VM already exists, and should say so and be usable

Closes #817. Refs #816.

## Problem

The owner asked for a VM kept for development and feature testing across all
work, rather than rebuilt and thrown away. Investigating that found the answer
already in the tree, and hidden.

`nixosConfigurations.vm-big` (`flake.nix:1317`) is persistent: `diskImage =
"./nixarchy-vm-big.qcow2"`, 32 GB, 8 cores, a 128 GB disk, port 2224 so it runs
beside `.#vm`, and `localAi` with `qwen3:8b` already configured.

`.#vm` is the opposite **on purpose**. `vm/configuration.nix:127` sets
`diskImage = null`, and the comment says why: Omarchy replays
`~/.local/state/omarchy/notifications/history/` on start, so a stale disk made
already-fixed failures keep reappearing on screen. That is not a wart to fix; it
is the reason the smoke test can be trusted.

Three things are wrong with the situation as it stands:

1. **Two default panels cannot be used in the persistent VM.** `vm-big` has
   neither `virtualisation.podman` nor `services.boxes`, so `nixarchy.podman`
   and `nixarchy.distrobox` are gated off — the two panels most worth testing by
   hand are the two that cannot run there.
2. **Nothing says `vm-big` is the development VM.** Its doc anchor is
   `docs/internals/flake.md#the-same-vm-with-room-to-run-a-model`, which frames
   it as the model VM. An agent reading only `.#vm`'s `diskImage = null` comment
   would reasonably conclude no persistent VM exists and build a third one — I
   nearly proposed exactly that before reading `vm-big`.
3. **Nobody owns clearing it.** `vm/configuration.nix` states the obligation
   — *"remember you then own clearing it"* — and no one has taken it. A 128 GB
   disk with no policy is a slow leak on p620, which also hosts all four CI
   runners.

## Proposed outcome

- Every default panel works in `vm-big`, so a feature can be tested by hand
  where it will actually be used.
- A reader can tell in one sentence which VM is which, and why the throwaway one
  is stateless *deliberately*.
- The disk has a stated home and a stated reset policy.

## Affected users and systems

Anyone developing nixarchy. `flake.nix`'s `vm-big`, and the docs that describe
the VMs. Nothing changes for an installed machine, and **`.#vm` is not touched**
— the whole point is that its statelessness is load-bearing.

## Constraints

- **`.#vm` keeps `diskImage = null`.** Not negotiable: a stale disk is how fixed
  bugs came back on screen.
- **The disk lives under `/mnt/data/vmtest/`**, never `/tmp` — a 32 GB tmpfs
  competing with the machine's RAM (AGENTS.md §5).
- **Podman and boxes pull images**, so the VM needs a network and disk headroom;
  the `boxes` demo scene already learned that 1 GB dies staging blobs in
  `/var/tmp`.
- Enlarging `vm-big` must not make it unrunnable on a smaller machine than p620,
  or it stops being a development tool for anyone else.

## Decided (owner, 2026-09-20)

1. **`vm-big` keeps its name.** It is a public flake attribute and a rename
   costs every caller and every doc reference for a word. The docs carry the
   second meaning instead.
2. **Podman and boxes are on by default in it**, not behind a flag: the point of
   this VM is to match a real machine, where both are on. The cost is the image
   pulls, paid by anyone using `vm-big`.
3. **Rebuild monthly.** A stated cadence rather than "delete when it misbehaves"
   — which is exactly the stale-disk failure `.#vm`'s comment warns about, just
   with a longer fuse.
