---
title: Gaming
---

# Gaming

Omarchy ships Steam and RetroArch, Battle.net, Lutris and Heroic, Moonlight
for streaming from a PC, Xbox Cloud Gaming and GeForce NOW for the cloud, and
Minecraft. All of it is under _Install > Gaming_ in the Omarchy menu
(`Super + Space`) here too, and _Remove > Gaming_ undoes it. Proton and the
Steam Deck are the same story on any Linux; see
[upstream's page](https://omarchy.org/manual/gaming/) for that part.

What changes is how each row installs. Some are plain packages, some are
NixOS modules, and two go through scripts that need a line in your
configuration first. The table is the whole page in short:

| Row | What it does here | Unfree? |
|---|---|---|
| Steam | enables `programs.steam` | yes |
| RetroArch | nixarchy's `retroarch`, 13 free cores | no |
| Xbox Controllers | enables `hardware.xpadneo` | no |
| Lutris | `pkgs.lutris` | no |
| Heroic (Epic Games) | `pkgs.heroic` | no |
| Minecraft | `pkgs.prismlauncher` | no |
| Xbox Cloud Gaming | a web app, no package at all | — |
| Battle.net | needs `pkgs.umu-launcher` in your config | — |
| NVIDIA GeForce NOW | needs `services.flatpak.enable` in your config | — |

The rows marked as packages or modules go into `~/.config/nixarchy/apps.nix`
like every other app, and _Install > Apply changes_ rebuilds with them. Unfree
rows need `nixpkgs.config.allowUnfree = true`.

## Steam

Steam is a NixOS module, not a package, and this is the one to understand
because it is the pattern. Steam's own binaries and every game it downloads
are built for a normal Linux filesystem layout: `/lib`, `/usr/lib`, libraries
where the FHS says they are. NixOS has none of those paths, so a bare `steam`
package starts and immediately fails to find its libraries.
`programs.steam.enable` builds an FHS environment — a private root with the
expected layout — and runs Steam inside it. That is why the row enables an
option rather than adding a package, and why installing `pkgs.steam` by hand
would not run.

The row also needs `allowUnfree`. The 32-bit half of the graphics stack,
which upstream adds with `omarchy-install-gaming-gpu-lib32`, is one option on
NixOS instead of a per-driver package:

```nix
hardware.graphics.enable32Bit = true;
```

Steam still takes 10–20 seconds to start with no feedback, as upstream warns.

## RetroArch

nixpkgs' `retroarch` is `retroarch-with-cores` built with an empty core
list: it installs cleanly and emulates nothing. The obvious fix,
`retroarch-full`, pulls in unfree cores, and an unfree package in the app
selection aborts the entire rebuild for everyone who has not set
`allowUnfree` — rather than failing on its own.

So nixarchy builds its own `retroarch`: every core Omarchy's picker offers
that nixpkgs ships under a free licence, minus the two largest. Thirteen
cores — bsnes for SNES, mesen for NES, gambatte and mgba for Game Boy,
blastem for Mega Drive, beetle-pce-fast, beetle-psx-hw, parallel-n64,
desmume, flycast, ppsspp, puae for Amiga and vice-x64 for the C64. snes9x and genesis-plus-gx are
unfree in nixpkgs, which is why bsnes and blastem cover those systems.

If you want the unfree ones — snes9x, genesis-plus-gx, mame, dolphin — set
`allowUnfree` and override the package in your `nixarchy-apps.nix`:

```nix
programs.nixarchy.apps.retroarch.package =
  pkgs.retroarch.withCores (c: [ c.snes9x c.mame c.dolphin ]);
```

That replaces the core list rather than adding to it, so name everything you
want.

Two things differ from upstream's walkthrough. RetroArch loads cores from
`/usr/lib/libretro` on Arch; here they live inside the package, and
`omarchy-retroarch-cores` prints the current directory if you need it. And
`~/Games/roms` and `~/Games/bios`, along with the CRT Royale shader preset,
are written by upstream's `omarchy-install-gaming-retroarch` script, whose
first step is a package install that stops here — so set your ROM and BIOS
directories in RetroArch's own settings after the first launch. The _RetroArch
Game Launcher_ row, which gives one game its own launcher entry, works.

## Xbox controllers

Bluetooth Xbox controllers need the `xpadneo` kernel driver. On Arch that is a
DKMS package; on NixOS an out-of-tree module has to be built against the
running kernel and loaded, which is what `hardware.xpadneo.enable` does, so
the row enables that option. Pair with `Super + Ctrl + B` afterwards. A
controller on a USB-C cable does not need it.

## Battle.net and GeForce NOW

These two run upstream's install scripts unchanged, and each begins by asking
`omarchy-pkg-add` for a package, which prints the declarative route and stops.
The route in each case is one line:

```nix
environment.systemPackages = [ pkgs.umu-launcher ];   # Battle.net
services.flatpak.enable = true;                       # GeForce NOW
```

Battle.net is a Windows installer run under umu-launcher; the wine prefix it
builds lives under `$HOME` and the rest of the script works once the launcher
exists. GeForce NOW ships only as a Flatpak, and Flatpak on NixOS is a service
rather than a package — without it there is nowhere for the app to be
installed. After the rebuild: `flatpak install flathub com.nvidia.geforcenow`.

## Xbox Cloud Gaming

A web app. It touches no package manager, so the row works exactly as
upstream describes.

## Minecraft

nixpkgs removed its `minecraft` launcher as broken, and its own removal
message points at Prism Launcher, so that is what the row installs — nixpkgs'
recommendation rather than a substitution invented here. Sign in with your
Microsoft account inside it.

## Moonlight and Sunshine

Moonlight is preinstalled and streams from a Windows PC running Sunshine
exactly as upstream says.

Hosting from this machine is different. Upstream's `omarchy install service
sunshine` installs Sunshine with pacman and opens its ports with ufw; here
the package step stops and there is no ufw. Add the package yourself and open
the ports where the rest of the firewall lives:

```nix
environment.systemPackages = [ pkgs.sunshine ];
networking.firewall.allowedTCPPorts = [ 47984 47989 48010 ];
networking.firewall.allowedUDPPorts = [ 47998 47999 48000 48002 48010 ];
```

Those are the ports upstream's script opens, minus 5353, which
`services.avahi` already has open. Upstream restricts them to private LAN
ranges and the Tailscale interface; `networking.firewall.interfaces.<name>`
does the same job if you want it.

## Lutris and Heroic

Plain packages, and upstream's advice applies: both look like nothing is
happening while a game installs. Give them time.
