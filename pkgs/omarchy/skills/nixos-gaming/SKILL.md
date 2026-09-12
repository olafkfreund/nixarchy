---
name: nixos-gaming
description: >
  REQUIRED for gaming on this NixOS machine — Steam and Proton, the 32-bit
  graphics stack, controllers, gamemode and gamescope, launchers, emulation and
  cloud gaming. Use when asked to install Steam, run a Windows game, fix a game
  that will not launch or shows no Vulkan device, choose or force a Proton
  version, pair an Xbox or PlayStation controller, add libretro cores to
  RetroArch, set up Lutris, Heroic, Battle.net, Minecraft, GeForce NOW or
  Moonlight, or host game streaming with Sunshine. Triggers: steam, programs.steam,
  proton, protontricks, PROTON_, STEAM_COMPAT, enable32Bit, lib32, vulkan, dxvk,
  vkd3d, gamemode, gamescope, mangohud, xpadneo, xone, Steam Input, lutris, heroic,
  bottles, umu-launcher, retroarch, libretro, emulation, prismlauncher, minecraft,
  sunshine, moonlight, geforce now, "game won't start".
  Drivers, CUDA/ROCm, VA-API and hybrid laptops belong to `nixos-gpu` — send
  driver questions there and stop.
---

# NixOS Gaming Skill

Gaming works well here, and nearly every "it does not work" report is one of
three things: the 32-bit half of the graphics stack is missing, Steam was
installed as a package instead of enabled as a module, or the driver underneath
was never set up at all.

**Where this skill stops.** Drivers — NVIDIA/CUDA, AMD/ROCm, Intel, VA-API,
hybrid/Optimus laptops — belong to the `nixos-gpu` skill. If `vulkaninfo` finds no
device, or the question is which driver branch or which bus id, go there and stop;
do not diagnose a driver from here. This skill owns everything from a working GPU
upwards.

Everything below is route 2 in the `nixos` skill: edit the configuration, then
rebuild. The Install ▸ Gaming rows in the Omarchy menu (`Super + Space`) write
the same lines into `~/.config/nixarchy/apps.nix`, and _Install ▸ Apply changes_
rebuilds with them.

## The thing people miss: the 32-bit graphics stack

Steam's runtime, most Proton builds and a great many older games are 32-bit. The
64-bit driver stack alone gives a game that starts and then dies with no Vulkan
device, or a black window — which reads as a broken game, not a missing option.

```nix
hardware.graphics = {
  enable = true;
  enable32Bit = true;        # this line
};
```

On NixOS this is one option for every driver. On Arch it is a per-driver lib32
package (`omarchy-install-gaming-gpu-lib32` upstream), which is why guides written
for Arch send people looking for packages that do not exist here.

Check before assuming:

```sh
vulkaninfo --summary | head -20            # does the 64-bit stack see the GPU?
nix shell nixpkgs#pkgsi686Linux.mesa-demos -c glxinfo | head   # and the 32-bit one
```

## Steam

**Steam is a NixOS module, not a package, and installing `pkgs.steam` by hand
does not run.** Steam's own binaries and every game it downloads expect `/lib`,
`/usr/lib` and the rest of an ordinary Linux layout. `programs.steam.enable`
builds an FHS environment — a private root with that layout — and runs Steam
inside it.

```nix
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;       # Steam Remote Play
    dedicatedServer.openFirewall = false; # only if hosting
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;       # a Steam Deck-style session, optional
  };
  hardware.graphics.enable32Bit = true;
}
```

Steam is unfree; nixarchy sets `allowUnfree` by default, so the row works as-is.
On a machine where that default was turned back off, `nixpkgs.config.allowUnfree
= true` is needed or the rebuild aborts.

**Steam takes 10–20 seconds to start with no feedback on the first run.** Say so
before someone concludes it is broken.

Extra packages go inside the FHS environment rather than into
`environment.systemPackages`, or Steam cannot see them:

```nix
programs.steam.extraPackages = with pkgs; [ gamemode mangohud ];
```

## Proton

Proton is Valve's Wine fork and it is **per title, not global**. Set it in Steam:
right-click the game ▸ _Properties_ ▸ _Compatibility_ ▸ force a specific tool.
There is no NixOS option for a game's Proton version, and there should not be —
the choice differs per title and lives in Steam's own config.

- **Proton Experimental** first for a title that fails on stable; it carries fixes
  before they are released.
- **Proton-GE** for titles needing media codecs or anti-cheat workarounds:
  `programs.steam.extraCompatPackages = [ pkgs.proton-ge-bin ];`, then pick it in
  the same menu. Do not hand-copy builds into `~/.steam/`; the option exists.
- Check <https://www.protondb.com> for a title before debugging it. Most
  "unplayable" reports there come with the exact launch option that fixes them.

Where the state lives, which matters when something is wedged:

| path | what |
|---|---|
| `~/.steam/steam/steamapps/compatdata/<appid>/` | the game's wine prefix |
| `~/.steam/steam/steamapps/shadercache/` | compiled shaders |
| `~/.steam/steam/steamapps/common/` | the games themselves |

Deleting a title's `compatdata` directory resets its prefix and is the standard
first move for a game that broke after an update. It loses in-prefix
configuration, not saves held in the game's own directory — say which before
recommending it.

Launch options go in the same Properties dialog, and the common ones are
environment variables:

```
PROTON_LOG=1 %command%              # writes ~/steam-<appid>.log
PROTON_USE_WINED3D=1 %command%      # fall back from DXVK, for a driver bug
PROTON_NO_ESYNC=1 %command%         # if the game dies on file-descriptor limits
DXVK_HUD=fps %command%              # a quick frame counter
MANGOHUD=1 %command%                # richer overlay, needs mangohud installed
gamemoderun %command%               # CPU governor and scheduling for this process
```

`protontricks` runs `winetricks` against a Steam prefix. It has its own option
inside the module — `programs.steam.protontricks.enable = true;` — which is the
one to use, because it lands inside Steam's FHS environment where the prefixes
are. Reach for it only when a title's ProtonDB page names a specific verb.

## Controllers

| controller | what it needs |
|---|---|
| Xbox, USB cable | nothing — `xpad` is in the kernel |
| Xbox, Bluetooth | `hardware.xpadneo.enable = true;` |
| Xbox, official wireless dongle | `hardware.xone.enable = true;` |
| PlayStation DualShock/DualSense | nothing — `hid-playstation` is in the kernel |
| Nintendo Pro / Joy-Con | nothing for the kernel; Steam Input for mapping |
| anything else, wrong or no mapping | Steam Input, or a udev rule |

`xpadneo` is an out-of-tree kernel module, so it has to be built against the
running kernel and loaded — that is why the Install ▸ Gaming row enables a
hardware option rather than adding a package, and why a kernel change rebuilds
it. Pair afterwards with `Super + Ctrl + B`.

Steam Input handles remapping, gyro and per-title profiles for everything above
and is almost always the right answer before writing udev rules. For a pad only
non-Steam software sees:

```nix
hardware.steam-hardware.enable = true;   # Valve's udev rules, also needed for the Steam Controller and Index
services.udev.packages = [ pkgs.game-devices-udev-rules ];
```

Diagnose before configuring:

```sh
ls /dev/input/js* /dev/input/event*
nix shell nixpkgs#evtest -c evtest      # does the kernel see button presses at all?
```

If `evtest` sees the buttons, the kernel side is done and the problem is mapping —
Steam Input, not a module.

## gamemode and gamescope

```nix
programs.gamemode.enable = true;    # governor, scheduling and I/O priority while a game runs
programs.gamescope = {
  enable = true;
  capSysNice = true;                # lets it raise its own priority
};
```

`gamemode` does nothing until a game asks for it: `gamemoderun %command%` as a
launch option, or a launcher that calls it. `gamescope` is a micro-compositor —
use it for a game that insists on changing the display mode, that scales badly on
a HiDPI screen, or that behaves poorly under a tiling Wayland compositor:

```
gamescope -W 2560 -H 1440 -r 144 -f -- %command%
```

`programs.steam.gamescopeSession.enable` gives a Steam Deck-style
big-picture session as a separate login option.

## Launchers, and what each Install ▸ Gaming row lands on

| Row | What it does here |
|---|---|
| Steam | enables `programs.steam` |
| RetroArch | nixarchy's own `retroarch`, 13 free cores |
| Xbox Controllers | enables `hardware.xpadneo` |
| Lutris | `pkgs.lutris` |
| Heroic (Epic Games) | `pkgs.heroic` |
| Minecraft | `pkgs.prismlauncher` |
| Xbox Cloud Gaming | a web app — no package at all |
| Battle.net | needs `pkgs.umu-launcher` in the configuration first |
| NVIDIA GeForce NOW | needs `services.flatpak.enable` first |

Two of those run upstream install scripts that begin by asking for a package,
which prints the declarative route and stops. The route is one line each:

```nix
environment.systemPackages = [ pkgs.umu-launcher ];   # Battle.net
services.flatpak.enable = true;                       # GeForce NOW
```

Then `flatpak install flathub com.nvidia.geforcenow` after the rebuild — GeForce
NOW ships only as a Flatpak, and Flatpak here is a service rather than a package,
so without it there is nowhere for the app to be installed.

Lutris and Heroic are plain packages. Both look like nothing is happening while a
game installs; give them time. Lutris wants `wine`, `winetricks` and
`gamemode` available to be useful — add them beside it rather than expecting the
launcher to fetch them.

## RetroArch and emulation

nixpkgs' `retroarch` is `retroarch-with-cores` built with an **empty core list**:
it installs cleanly and emulates nothing. `retroarch-full` pulls in unfree cores,
and an unfree package aborts the whole rebuild rather than failing on its own for
anyone who turned `allowUnfree` back off.

So nixarchy builds its own `retroarch` with thirteen free cores: bsnes (SNES),
mesen (NES), gambatte and mgba (Game Boy), blastem (Mega Drive),
beetle-pce-fast, beetle-psx-hw, parallel-n64, desmume, flycast, ppsspp, puae
(Amiga) and vice-x64 (C64). snes9x and genesis-plus-gx are unfree in nixpkgs,
which is why bsnes and blastem cover those systems.

For the unfree ones, override the package rather than switching to
`retroarch-full`:

```nix
programs.nixarchy.apps.retroarch.package =
  pkgs.retroarch.withCores (c: [ c.snes9x c.mame c.dolphin ]);
```

**That replaces the core list rather than adding to it** — name everything you
want, including the ones you were happy with.

Two differences from every guide written for Arch:

- Cores are **inside the package**, not in `/usr/lib/libretro`. Nothing to copy,
  nothing to point at; `omarchy-retroarch-cores` prints the current directory if
  something asks for a path.
- `~/Games/roms`, `~/Games/bios` and the CRT Royale shader preset are written by
  an upstream install script whose first step is a package install that stops
  here. Set the ROM and BIOS directories in RetroArch's own settings after the
  first launch.

Standalone emulators are ordinary packages: `dolphin-emu`, `pcsx2`, `rpcs3`,
`duckstation`, `cemu`, `ryujinx`. Most want `enable32Bit` and a Vulkan-capable
driver, which is the first section of this skill again.

## Streaming

Moonlight is preinstalled and streams *from* a Windows PC running Sunshine with
no configuration here.

Hosting *from* this machine needs the package and the ports, and there is no ufw:

```nix
environment.systemPackages = [ pkgs.sunshine ];
networking.firewall.allowedTCPPorts = [ 47984 47989 48010 ];
networking.firewall.allowedUDPPorts = [ 47998 47999 48000 48002 48010 ];
```

Those are the ports upstream's script opens, minus 5353, which `services.avahi`
already has. `networking.firewall.interfaces.<name>` restricts them to a LAN or a
Tailscale interface if that is wanted — see the `nixos-security` skill.

## Troubleshooting

```sh
vulkaninfo --summary | head -20             # a GPU here, or a driver problem (-> nixos-gpu)
glxinfo -B | grep -i 'renderer\|opengl'     # llvmpipe means software rendering
journalctl --user -b | grep -i steam
cat ~/steam-<appid>.log                     # with PROTON_LOG=1 %command%
```

| Symptom | Cause |
|---|---|
| Steam installed but will not run | Installed as `pkgs.steam`. It has to be `programs.steam.enable` |
| Game starts, then exits instantly, no window | Missing 32-bit stack: `hardware.graphics.enable32Bit` |
| "No Vulkan device" / "failed to create device" | Driver layer, not gaming — `nixos-gpu` |
| Renderer says `llvmpipe` | Software rendering: the driver is not loaded at all — `nixos-gpu` |
| Works on the iGPU, not the dGPU, on a laptop | PRIME offload — `nixos-gpu` |
| Game ran last week, not today | Proton version moved, or a wedged prefix. Force the old Proton, or reset `compatdata` |
| Anti-cheat kicks the player | Usually unsupported by the publisher on Linux. Check ProtonDB before spending a rebuild |
| Controller seen by `evtest`, not by the game | Mapping, not kernel: Steam Input |
| Bluetooth Xbox pad will not pair | `hardware.xpadneo.enable`, and reboot into the new kernel module |
| RetroArch lists no cores | Plain `pkgs.retroarch` somewhere in the config, shadowing nixarchy's |
| Unfree licence error on a rebuild | `nixpkgs.config.allowUnfree = true;` |

## Rules

- **Check `enable32Bit` before anything else.** It is one line and it is the
  cause more often than everything below it combined.
- **Never install `pkgs.steam`.** It is a module here for a reason that cannot be
  worked around with a package.
- **Send driver questions to `nixos-gpu` and stop.** Two skills answering "the
  GPU does not work" is how a user gets two contradictory diagnoses.
- **Proton version is per title.** Do not write configuration for it.
- **Read ProtonDB before debugging a specific title.** The fix is usually a
  documented launch option, not a system change.
- **A kernel module change — `xpadneo`, `xone` — needs a reboot**, not just
  `switch`. Say so before claiming the change did not work.
- **Warn before deleting a prefix.** `compatdata` removal is routine and it is
  still destruction of the user's in-game settings.
