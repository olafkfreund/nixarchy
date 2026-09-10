---
title: Preview changes
---

# Preview changes

`nixarchy preview` (or Omarchy menu → Install → **Preview changes**) builds
what your `/etc/nixos` evaluates to *right now* and boots it in a VM window
— so you can look at a configuration change before switching the machine to
it. Apply changes offers the same thing as a question, at the moment you are
about to switch.

Underneath it is `nixosConfigurations.<host>.config.system.build.vm`: your
own configuration re-evaluated with nixpkgs' `qemu-vm.nix` layered on — the
same thing `nixos-rebuild build-vm` builds. The guest shares your machine's
`/nix/store` read-only, so the first preview builds the *delta* of your
change, not a second copy of the desktop, and the disk image carries state
rather than a system.

## What a green preview proves, and what it does not

A preview is **strong evidence, not proof**. The VM re-evaluates your
configuration with VM filesystems and a VM bootloader, so its toplevel is
not the one `nixos-rebuild switch` would activate. What it verifies: your
options evaluate, your services start, your session comes up. What it does
not verify: your bootloader, your real GPU, your real disks. A change that
touches any of those still meets its first real test at the switch — which
is one `nixarchy rollback` away from undone.

## The disk, and why the command sometimes refuses

Each preview gets a disk image in `~/.local/share/nixarchy/preview/`. Left
to its own devices, qemu's runner would reuse that disk forever — and a
reused disk replays the *previous* preview's state (logins, notification
history, anything written in the guest) into the one you are looking at,
which quietly turns "what does my change do?" into "what did my last
preview do?".

So when a previous preview's disk is there, the command refuses to guess:

- `nixarchy preview --fresh` — delete it and preview on a clean disk
- `nixarchy preview --keep` — boot on it, previous state and all

`--keep` is for looking at something that needs state to exist — a second
boot, a service that migrates data. Everything else wants `--fresh`.

## Speed

Without `/dev/kvm` (no hardware virtualisation, or you are not in the
`kvm` group) the preview runs under software emulation, several times
slower — near-unusable for a graphical desktop. The command warns loudly;
the lag is the emulation, not your configuration. The guest gets 8192 MB
by default; `--memory 4096` runs a smaller one, and 4096 is the floor.

## Not Sandboxes

[Sandboxes](sandboxes) (`nixarchy vm`) are disposable *generic* NixOS
MicroVMs — a clean room for software you do not trust. A preview is the
opposite: **your own configuration**, booted to be looked at. The sandbox
page says "Not nixarchy's own test VM" about itself; this is that VM.
