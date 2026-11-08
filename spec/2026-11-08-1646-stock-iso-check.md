---
status: draft
issue: 1646
intent: intent/2026-11-08-1646-stock-iso-check.md
---

# Spec: a check proves the stock NixOS ISO install path (#1646 Part B)

## What Part A did, stated correctly

`offline_by_design` (`installer/install.sh:2511-2515`) is true when
`nix config show substituters` is **empty**. That is the offline install
test VMs, which set `substituters = mkForce [ ]` (Part A plan, decision 2).
On them the preflight is skipped. A stock NixOS ISO **has** a substituter
(`cache.nixos.org`), so on it the preflight runs, and `SUBSTITUTE_FLAGS`
(`install.sh:73`) adds our caches to every nix call that plans or builds
(decision 4). The intent's first paragraph says this backwards, and is
corrected in its own commit.

What is already proven: `checks.installer-refusal` runs the real installer
on a stock-shaped VM with no image marker, and proves the dark-cache refusal
leaves the disk bare (`tests/installer-refusal.nix:2-30`). It is a
NixOS test node with our `install` package in its closure, not the stock ISO
file.

**The gap is booting the actual stock ISO and completing an install from
it.** There is no dark-cache case, because `installer-refusal` already
covers the refusal and the stock ISO adds nothing to it.

## Design

### 1. `tests/install-stock-iso.nix`

A `runNixOSTest` with two machines on the test network:

- **`server`**, an ordinary test node. It runs nginx with a self-signed
  certificate for `nixarchy.cachix.org` and `hyprland.cachix.org`, the
  `installer-refusal` pattern (`tests/installer-refusal.nix:37-44`). It
  serves a binary cache made by `pkgs.mkBinaryCache` from the reference
  install's closure plus the `install` package. It also exports a 9p share
  holding that cache's CA certificate, an answers file naming the target
  disk, and the `install` store path.
- **`stock`**, made with `create_machine` and a start command that boots the
  pinned ISO as `-cdrom`. The kernel and initrd are extracted from that ISO
  by a small derivation, and booted with the ISO's own kernel parameters
  plus `console=ttyS0`, because the stock image has no test backdoor and the
  serial console is the only scriptable way in. It gets a blank 32 GiB
  virtio target and the 9p share (virtfs; 9p is a module in the stock
  kernel).

Over serial the driver runs, as root on the live ISO:

1. `modprobe 9pnet_virtio` and mount the share; map both cache hostnames to
   `server` in `/etc/hosts` (writable on the live overlay); export
   `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` to the share's CA bundle.
2. `nix copy --from file:///mnt/share/cache --no-check-sigs <install>`. That
   brings in the installer, which would be `nix run github:...#install` in
   the manual, and is out of reach with no internet (see limits).
3. `<install>/bin/nixarchy-install --answers /mnt/share/answers`.

It asserts the install exits 0, and that the target holds a NixOS system
whose `/etc/nixarchy/` names the expected host. It prints three numbers:

- time to the first installer log line;
- bytes served, from nginx's access log;
- peak overlay use, `df` on the live store's overlay, sampled during the run.

### 2. The ISO pin

`data/stock-iso.nix` holds `{ url; hash; }` for the 26.05 minimal ISO
(intent decision 2), pinned to an exact `releases.nixos.org/nixos/26.05/...`
path, never the moving `latest-` link. It is refreshed by hand: a new hash
from `nix store prefetch-file`, in a one-line PR. The nightly review gains
no row. A stale pin still tests the path; it is only an older point release.

### 3. Placement (intent decision 1)

`install-stock-iso` joins `nightly_only` in
`.github/scripts/generated-checks.sh:77`. `nightly.yml` gains a job beside
`install-iso-net` (`:140`) on the self-hosted install label, added to
`report`'s `needs`. **A CI-workflow change: the owner merges it (§4, §11).**

### 4. Manual

`docs/manual/the-iso.md` gains "From a stock NixOS ISO": boot the stock
minimal ISO, connect to the network, run `nix run github:olafkfreund/nixarchy#install`.
It explains the preflight (what happens when our caches are unreachable),
and the RAM note from `check_store_space`.

## Alternatives rejected

- **A NixOS test node "shaped like" the stock ISO.** That is
  `installer-refusal`. It cannot tell whether the real image's `nix.conf`,
  kernel or overlay behave as assumed, which is the whole gap.
- **Driving the stock ISO through the screen (OCR).** Slow and flaky; the
  serial console is exact.
- **Fetching the installer from GitHub inside the VM.** The test network
  has no internet.

## Risks

- **Size and time.** The binary cache holds a full system closure, several
  GB, built and served each night. That is the nightly budget's call
  (decision 1), and why this never runs on a pull request.
- **Kernel-parameter extraction** depends on the ISO's GRUB/isolinux
  layout. A new point release that changes it fails the extraction
  derivation loudly, not the install.
- **Limit:** the manual's `github:` fetch is not exercised. The test proves
  everything after the installer is on the machine.

## Verification

- The check passes nightly-style locally, at the VM tier with the gate free
  and one slot.
- §1: drop the `extra-substituters` and `extra-trusted-public-keys` options
  from `SUBSTITUTE_FLAGS` (`install.sh:73`). The stock ISO then knows only
  `cache.nixos.org`, which is unreachable here, so the preflight refuses, or
  the build has to start from source and fails at the check's timeout. The
  check must go red, with the output captured.
- `checks.install-gate` and `generated-checks.sh`'s own guard (the nightly
  list membership) stay green; fmt, statix, deadnix.
