---
status: approved
issue: 1377
intent: intent/2026-10-20-1377-edge-etc-overlay.md
---

# Spec: edge knows what every file in quattro's /etc is for

## What reading the 13 files found

Each file was read at quattro 4f920a2, edge's pin. Each was compared with
what nixarchy already does, by searching for the behaviour rather than the
file name (§12). The classes are those in the header of
`data/etc-overlay.nix`: native, installed, seed, covered, na and
divergent.

Nixarchy cannot `install` a systemd drop-in, because `/etc/systemd/system`
and `/etc/systemd/user` are single store symlinks. Every existing drop-in
row is therefore `native`, and the four below follow suit.

| file | does | class | equivalent here |
|---|---|---|---|
| `xkb/rules/evdev` + `xkb/symbols/omarchy` | define `omarchy:shift_caps_compose`, which quattro's `default/hypr/input.lua:16` **always sets**. Shift+Caps is Compose, and Caps alone is still Caps Lock | **installed** (both) | none needed. libxkbcommon searches `/etc/xkb` first, and `installedEtc` (`modules/nixos.nix:45,1703`) already turns these rows into `environment.etc`. **Today the option cannot resolve on edge, so Compose does not work** |
| `mpv/mpv.conf` | `hwdec=auto-safe` | **installed** | none needed. libmpv reads `/etc/mpv`, and `~/.config/mpv` still overrides it |
| `sysctl.d/90-omarchy-arp.conf` | `arp_ignore=1`, `arp_announce=2` (all/default), so Wi-Fi does not answer ARP for a dock's Ethernet address | **native** | 4 lines of `boot.kernel.sysctl` at `mkDefault`, beside the existing sysctl block (~`modules/nixos.nix:2159`) |
| `systemd/system.conf.d/20-mount-events.conf` | PID 1's mount-event burst raised from 5 to 30 a second, so boot does not defer mounts | **native** | `systemd.managerEnvironment.SYSTEMD_DEFAULT_MOUNT_RATE_LIMIT_BURST = "30";`, which is the option nixpkgs fills `ManagerEnvironment` from |
| `systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf` | `KillMode=mixed`, so the compositor stops before its shell clients | **native** | `systemd.user.services."wayland-wm@".serviceConfig.KillMode = "mixed";`. On the template, because uwsm names the instance `start\x2dhyprland` here, so upstream's instance name never matches |
| `sudoers.d/omarchy-locale-generate` | NOPASSWD for the locale generator | **covered** | already: the generator is a stub here, and `programs.nixarchy.language` builds locales with the system |
| `mkinitcpio.conf.d/00-omarchy-hooks.conf` | the platform's HOOKS baseline | **na** | NixOS builds its initrd from `boot.initrd.*` |
| `mise/conf.d/omarchy-tools.toml` | lazy mise installs of about 22 tools (node, gh, claude, codex…) | **divergent** | deliberately none: it would put mise downloads ahead of the Nix builds, which is what `data/apps.nix` and #707 exist to prevent |
| `mise/conf.d/omarchy-agent-accounts.toml` | mise `[wrappers]` routing claude/codex/grok through `omarchy-agent-account-exec` | **divergent**, pointing at a new issue | not a line or two: whether nixarchy's mise supports `[wrappers]`, and how it interacts with Nix-installed CLIs, is unverified |
| `udev/rules.d/60-omarchy-io-scheduler.rules` | Kyber on every whole disk | **divergent**, pointing at the same new issue | not ported here. A udev rule cannot be `mkDefault`, so it would silently override a host's own scheduler (p620 runs bfq). That is a §14 coexistence change, and needs its own design |
| `systemd/system/systemd-binfmt.service.d/10-eager-mount.conf` + `proc-sys-fs-binfmt_misc.mount.d/10-omarchy-conditions.conf` | binfmt_misc mounted eagerly, with matching conditions | **divergent**, pointing at the same new issue | not ported: no boot-time binfmt deferral has been seen here, and the pair needs `overrideStrategy = "asDropin"` units, so it is not a line or two |

This follows the approved split: what is a line or two is implemented, and
the rest goes into one follow-up issue. That issue is filed during
implementation, titled "Port quattro's storage, binfmt and agent-account
/etc tuning", and the three divergent rows name it.

## Design

### 1. Rows and module lines, on `edge-candidate` only

- **`data/etc-overlay.nix`:** 13 rows, with classes and reasons as in the
  table above, written in the existing rows' style.
- **`modules/nixos.nix`:** the three `native` equivalents, which are the
  ARP sysctls (`mkDefault`), `managerEnvironment` and the `wayland-wm@`
  `KillMode`. Each gets a one-line comment naming the quattro file. These
  are edge-only, because stable 4.0.6's Omarchy does not ship these files,
  and stable keeps "what the Omarchy release does". They reach `main` when
  a release carries them.
- **Merge safety (the intent's constraint):** the rows are inserted in
  key order, which is where `main` and `edge` already agree, and the
  module lines go beside existing edge-agnostic blocks. A trial merge of
  `main` into the new candidate must keep every row and line.

### 2. Edge verify runs `etc-overlay`, on `main`

Add `etc-overlay` to the check list in `.github/workflows/omarchy-edge.yml:239`.
It is one word, a CI-gate change (§11), merged by you, and **merged after
§1 is on `edge-candidate`**, so the next edge run is not red on day one.
#1383 later replaces the hand-kept list with the generated one; this
one-word change is what holds until then.

### Interaction with #1380

Edge is currently blocked on #1380 (the notification engine). §1 is pushed
to `edge-candidate` regardless, since rows and modules are independent of
that patch, and it publishes with the first edge run that promotes. The
overlay check reads quattro's shipped tree, so if #1380's newer quattro
adds or drops an `/etc` file, the rows are re-checked against that pin in
#1380's run.

## Coexistence (§14)

- **sysctl:** `mkDefault`, so a user's own `boot.kernel.sysctl` value
  wins.
- **`managerEnvironment`:** an attrset, so a user's entries merge, and
  only the same key conflicts. That is unlikely, and nixpkgs reports it
  as a definition conflict rather than silently.
- **`KillMode`:** a user who sets `KillMode` on `wayland-wm@` conflicts
  loudly at evaluation. That is acceptable for a session unit nixarchy
  owns.
- **`/etc/xkb` and `/etc/mpv`:** if a user already declares
  `environment.etc."xkb/…"` or `"mpv/mpv.conf"`, the two definitions
  collide loudly at evaluation, which is the existing behaviour of every
  `installed` row.

No fixture is added: none of these is a silent clash of the
`systemPackages` kind.

## Verification (§1)

- `checks.etc-overlay` on the edge candidate:
  - **red** before the change, listing all 13 (measured on 2026-10-20);
  - **green** after;
  - **red** again with one row removed, naming that file.
- **The workflow step:** in a scratch copy of the candidate with one row
  removed, edge's verify loop (`try etc-overlay nix build …`) puts
  `etc-overlay` in `failed=` and exits 1.
- `nix eval` of `nixosConfigurations.reference` on the candidate:
  - the three sysctls, `managerEnvironment` and `KillMode` are set;
  - `environment.etc` has `xkb/rules/evdev`, `xkb/symbols/omarchy` and
    `mpv/mpv.conf`.
- **On p620, after edge publishes:** the active XKB keymap includes the
  `omarchy` symbols, so Shift+Caps composes, and
  `sysctl net.ipv4.conf.all.arp_ignore` reads 1.
