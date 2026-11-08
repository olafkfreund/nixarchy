---
status: approved
issue: 1646
intent: intent/2026-11-08-1646-stock-iso-check.md
---

# Spec: a check proves the stock NixOS ISO install path (#1646 Part B)

## What Part A did

`offline_by_design` (`installer/install.sh:2511-2515`) is true when
`nix config show substituters` is **empty**, which is the offline install test
VMs (`substituters = mkForce [ ]`; Part A plan, decision 2), and there the
preflight is skipped. A stock NixOS ISO has `cache.nixos.org` configured, so
on it `preflight_build` runs (`:2578`): it probes `https://cache.nixos.org`
and our caches over HTTP (`:2582-2584`), then dry-runs the build with
`SUBSTITUTE_FLAGS` (`:73`, used at `:2600`).

`checks.installer-refusal` already proves the dark-cache refusal on a
stock-shaped test node (`tests/installer-refusal.nix:2-30`). **The gap is
booting the actual stock ISO and completing an install from it.** There is
no dark-cache case.

## Design

### 1. `tests/install-stock-iso.nix`

A `runNixOSTest` with two machines on the test network.

**`server`**, an ordinary test node, runs nginx with one self-signed
certificate covering three names, the `installer-refusal` pattern
(`tests/installer-refusal.nix:37-44`):

- `cache.nixos.org` is served as an **empty cache**: `nix-cache-info` answers
  200 and every `.narinfo` 404s. The installer probes this host first
  (`install.sh:261,291`, `:2582`), so it must answer. Serving nothing from
  it is what lets section 3's break isolate our flags.
- `nixarchy.cachix.org` and `hyprland.cachix.org` serve one binary cache from
  `pkgs.mkBinaryCache`. Its roots are the reference install's closure, the
  `install` package, and every path in `inputs.self.lib.inputSources`
  (`flake.nix:1586`): the source trees the generated flake's locked inputs
  resolve to (section 2).
- A 9p share holds the CA certificate, an answers file naming the target
  disk, and the `install` store path.

**`stock`** is made with `create_machine` and a start command that boots
the pinned ISO:

- **UEFI**, with OVMF firmware (`pkgs.OVMF.fd`, code and a writable vars
  copy as pflash), because the installer refuses without
  `/sys/firmware/efi` (`require_root_and_uefi`, `install.sh:225`).
- The ISO as `-cdrom`. Its kernel and initrd are extracted by a small
  derivation and booted with the ISO's own kernel parameters plus
  `console=ttyS0`: the stock image has no test backdoor, so the serial
  console is the scriptable way in.
- A blank 32 GiB virtio target and the 9p share (virtfs; 9p is a module in
  the stock kernel).

Over serial, as root on the live ISO:

1. `test -d /sys/firmware/efi` (the probe confirms UEFI first and fails by
   name otherwise); `modprobe 9pnet_virtio`; mount the share; map the
   three hostnames to `server` in `/etc/hosts` (the live overlay is
   writable); export `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` to the share's
   CA bundle.
2. `nix copy --from https://nixarchy.cachix.org --no-check-sigs <install>`.
   That is the installer, which the manual fetches with
   `nix run github:olafkfreund/nixarchy#install`; GitHub is out of reach
   here (see limits).
3. `<install>/bin/nixarchy-install --answers /mnt/share/answers`.

It asserts exit 0, and that the target holds a NixOS system whose
`/etc/nixarchy/` names the answers file's host. It prints three numbers:
time to the first installer log line, bytes served (from nginx's access
log), and peak overlay use (`df` on the live store's overlay, sampled
during the run).

### 2. The generated flake's inputs, offline

The installer writes a flake that pins nixarchy by commit
(`installer/mkFlake.nix:25`, `github:olafkfreund/nixarchy/<rev>`), and
locks every other input with a `narHash`. Nix resolves a locked input with
a `narHash` by its store path, and asks the configured substituters for it
before fetching. So with every `inputSources` path in the binary cache, and
our cache on the call through `SUBSTITUTE_FLAGS`, evaluation never needs
GitHub. That is the mechanism `lib.inputSources` exists for: the shipped
ISOs root the same paths in their store. The install case proves it end to
end, and the plan's first step confirms that `inputSources` covers the lock
the generated flake writes.

### 3. The §1 break, isolated to `SUBSTITUTE_FLAGS`

Drop the `extra-substituters` and `extra-trusted-public-keys` options from
`SUBSTITUTE_FLAGS` (`install.sh:73`). Every HTTP probe still passes,
because `preflight_build`'s `curl` loop does not use the flags. The
dry-run (`:2600`) then knows only `cache.nixos.org`, which is the empty stub,
so the locked inputs cannot be substituted. Fetching them from GitHub fails
offline, and the installer refuses with "the system cannot be planned, so no
install was started". The check must go red with that line, and the
output is captured for the PR. No other change explains that failure,
since the network, the probes and the caches are all up.

### 4. The ISO pin

`data/stock-iso.nix` holds `{ url; hash; }` for the 26.05 minimal ISO,
pinned to an exact `releases.nixos.org/nixos/26.05/...` path, never the
moving `latest-` link. It is refreshed by hand: a new hash from
`nix store prefetch-file`, in a one-line PR. A stale pin still tests the
path; it is only an older point release.

### 5. Placement (owner decision 1: weekly)

`generated-checks.sh` builds on pull requests every check not in `claimed`
or `exempt` (`:127`). So `install-stock-iso` joins `claimed` (`:43`), named
by its weekly job, and `nightly_only` (`:77`), the list a keep-alive must
never rebuild, despite the name. `weekly.yml` gains a job, on the
self-hosted install label, beside `stable-session` (`:90`).
**A CI-workflow change: the owner merges it (§4, §11).**

### 6. Manual

`docs/manual/the-iso.md` gains "From a stock NixOS ISO": boot it in UEFI
mode, connect to the network, and run `nix run github:olafkfreund/nixarchy#install`.
It explains the preflight, and the RAM note from `check_store_space`.

## Alternatives rejected

- **A test node shaped like the stock ISO.** That is `installer-refusal`,
  and it cannot tell whether the real image's `nix.conf`, kernel and overlay
  behave as assumed.
- **Driving the stock ISO through the screen (OCR).** Slow and flaky; the
  serial console is exact.
- **Fetching the installer from GitHub inside the VM.** There is no
  internet on the test network.

## Risks

- **Size and time.** The binary cache holds a full system closure plus
  the input sources, several GB, built and served each week. That is the
  weekly budget's call, and the reason it never runs on a pull request.
- **Kernel-parameter extraction** depends on the ISO's boot layout. A
  point release that changes it fails the extraction derivation loudly, not
  the install.
- **Limit:** the manual's `github:` fetch of the installer is not
  exercised. The test proves everything from "the installer is on the
  machine" onward, including the offline resolution of the generated
  flake's inputs.

## Verification

- The check passes locally at the VM tier, with the gate free and one slot.
- §1 per section 3: drop our caches from `SUBSTITUTE_FLAGS`, and the check
  fails on "the system cannot be planned"; restore them and it passes.
- `generated-checks.sh`'s guard: `install-stock-iso` is absent from the
  `generated` (pull-request) list, and claimed by a workflow
  (`weekly.yml`).
- `checks.install-gate`, fmt, statix, deadnix.

## Decisions (owner, 2026-11-08, on the draft)

1. **Weekly, not nightly** (this replaces the intent's "nightly"). The check goes in the weekly workflow; it is still a CI change the owner merges.
