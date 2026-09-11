---
title: Troubleshooting
---

# Troubleshooting

Before any of this: if you are wondering whether a problem is *yours* or
*ours*, [how this is tested](how-this-is-tested) says what CI proves about
each release and — more usefully — what it deliberately does not.

### Start with the doctor

```sh
nix run github:olafkfreund/nixarchy#doctor
```

It reads the running system and reports the things that are most often the
actual problem on a NixOS host:

| Report | What it means |
|---|---|
| Session | Your session runs an older Omarchy build than the system; log out and in (below) |
| Default browser | `~/.config/mimeapps.list` is a store symlink, so *Setup > Default browser* is a silent no-op; or `$BROWSER` is set and shadows the default |
| Hyprland config | Which of `~/.config/hypr/*.lua` are yours and which Home Manager owns |
| Boot splash | Whether Omarchy's Plymouth theme is the one in use, or stylix's |
| TLP | TLP is on, so power-profiles-daemon is off and `omarchy powerprofiles` cannot work |

### `libGL.so.1: cannot open shared object file: No such file or directory`

Or `libstdc++.so.6`, or any other `.so` -- from a pip wheel at `import`, a
Node native module, or a downloaded binary. The binary is a prebuilt Linux
binary looking for its libraries where every other distro keeps them, and
NixOS keeps them elsewhere; [Prebuilt binaries](prebuilt-binaries) is the
full story. The machine can diagnose it -- hand the doctor the binary, as a
path or a command name:

```sh
nixarchy-doctor ~/.venv/lib/python3.12/site-packages/cv2/cv2.so
nixarchy-doctor some-downloaded-tool
```

It runs the loader's own resolution against the nix-ld library set, names
each missing library, and for the common ones prints the
`programs.nix-ld.libraries` line that fixes it -- for the rest, how to find
the package that carries the file. After the rebuild, **log out and back in**:
`NIX_LD_LIBRARY_PATH` is set at login, so the session you are sitting in
keeps the old list.

What it cannot do, so a clean report is not a guarantee:

- It checks only the files you name. The report's no-argument scan covers
  `~/.local/bin` and nothing else -- it does not crawl your venvs or
  `node_modules`, so for a broken import, name the actual `.so` inside the
  package (the traceback usually names it for you).
- It answers "is every library findable", not "is every library right". A
  library that is present but the wrong ABI or the wrong generation loads
  cleanly and misbehaves later; the doctor reports it as found.
- It resolves what the binary declares it needs. A library the program
  `dlopen`s by hand at run time is invisible until that moment, so a
  binary can pass the check and still fail later with the same error --
  bring the doctor the library name from *that* error and add it the same
  way.

### I broke my system with an update!

Roll back the generation, from the desktop or from the boot menu; see
[system snapshots](system-snapshots.md). There is no `omarchy-snapshot` to
restore here; the boot menu is the restore.

Upstream's last resort is `omarchy-reinstall`. **It exists here and cannot
finish.** It calls `omarchy-reinstall-pkgs`, whose first real step is
`sudo pacman -Suu`; the pacman shim refuses with a message and exits 1, and
`set -e` aborts the script before `omarchy-reinstall-configs` is reached. So
it neither reinstalls packages (a rebuild does that) nor resets a config, and
it is not a recovery route. Use instead:

| Want | Run |
|---|---|
| The packages back as they were | `sudo nixos-rebuild --rollback switch`, or the boot menu |
| One shipped config back to default | `omarchy refresh config <path>`, e.g. `omarchy refresh config hypr/bindings.lua`; it backs up your copy first |
| A report to attach to an issue | `omarchy debug --no-sudo --print` |

Always pass both flags to `omarchy debug`: `--no-sudo` skips `dmesg`, and
`--print` writes to the terminal instead of trying to upload. The pacman
lines in its output read `unknown`, which is expected.

### `omarchy update` says it updated, but nothing ever moves

If this machine was installed before the fix, its flake **can never move**, and
the update said so is the worst part of it: inputs were reported as going
forward while nothing did. No nixpkgs updates, no security fixes.

The cause is exact. The old installer wrote a *commit* into both the nixarchy
URL in `flake.nix` and the lock's `original` field — and `nix flake update`
re-resolves `original`. Re-resolving a commit returns that commit, forever.

```
nixarchy unfreeze
```

rewrites the two things the installer got wrong, in place: the nixarchy input
moves from a commit to the release branch, and nixpkgs becomes an input of your
own that nixarchy follows.

It only ever rewrites the installer's own line. If you have edited that URL
into some other shape, the flake has an owner with opinions and the command
refuses rather than editing around you.

Nothing to do if you installed recently — new machines are not written this
way. `nixarchy doctor` is the quick way to tell.

### My change rebuilt fine but the keybinding still runs the old thing

`OMARCHY_PATH` and `PATH` are set at login. A rebuild produces a new store
path and cannot change a session that is already running, so every
`omarchy-*` command the desktop executes comes from the old build until you
log out and back in.

```sh
echo "$OMARCHY_PATH"
readlink -f /run/current-system/sw/bin/omarchy | sed 's|/bin/omarchy$||'
```

If those differ, log out. The doctor reports this under **Session**. It is the
most misleading failure on this system, because running the new script by its
full store path works while the keybinding does not.

Related: if Home Manager deployed `~/.config/hypr/`, a rebuild swaps a
symlink rather than changing a file, and Hyprland's auto-reload does not see
it. Run `hyprctl reload`.

### I picked an app in Install and it never appeared

Three things to check, in order:

1. Did you *Apply changes*? Picking only edits `~/.config/nixarchy/apps.nix`.
2. Does your flake `imports = [ ./nixarchy-apps.nix ];`? Without it the
   rebuild succeeds and installs nothing. `nixarchy-apply` warns when nothing
   imports the file.
3. Is the app one you already had? The menu dims rows for apps already on
   `PATH`, and the doctor lists them under *Omarchy apps you already have*.

### Why are some apps so large on my display?

Unchanged from upstream: `GDK_SCALE` is 2 in `~/.config/hypr/monitors.lua`;
set `local omarchy_gdk_scale = 2` to 1 for a 1x display. That file is yours
and takes effect on save, no rebuild. See
[monitors](https://omarchy.org/manual/monitors/).

### Why isn't Caps Lock working?

Unchanged: Caps Lock is the compose key. Remap it in `~/.config/hypr/input.lua`
as upstream shows, `kb_options = "compose:ralt"`. Same file rule: yours, no
rebuild.

### My Wi-Fi, Bluetooth, audio, or trackpad just stopped working

Unchanged: *Update > Hardware* restarts the subsystem, and the
`omarchy-restart-*` commands behind those rows are upstream's.

### I can't see my Wi-Fi at all

Different from the section above: that one is for a radio that worked and
stopped. This is for one that never appeared.

**Look for the right name first, because it is free and it is usually this.**
There is no `wlan0` on a modern NixOS and there never will be — systemd renames
every interface after the PCI slot it sits in, so an Intel card at `00:14.3`
becomes `wlp0s20f3`. Someone searching nmtui for "wlan0" finds nothing on a
machine whose Wi-Fi is working perfectly:

```
ip link
```

If a `wlp*` device is listed, the card is fine — connect with
`nmcli device wifi list`, or pick it in nmtui.

**If no wireless device is listed at all**, the kernel has no interface, and
every wireless tool will show the same nothing, because they all ask the kernel.
Reaching for a different client — iwctl instead of nmtui — is a second way to
see the same absence. Ask what the driver did instead:

```
journalctl -b -k | grep -i firmware
nixarchy doctor
```

The doctor's **Wireless** section names which of three cases you are in: no PCI
device at all, a device with no driver bound, or a driver bound that registered
no interface. Those have three different fixes, and nmtui cannot tell them
apart.

**On a machine installed before v4.0.2-11**, the likeliest answer is that it has
no firmware at all. `hardware.enableRedistributableFirmware` was true on the ISO
and false on the installed system, so `linux-firmware` — which carries every
iwlwifi, ath, rtw and mt76 blob — was never installed. The symptom is
distinctive: Wi-Fi works while you are installing and is gone once you reboot,
and `lspci -nnk` still shows the driver bound, because a driver binds without
firmware and only then fails to register a radio.

Either update the machine, or add the line yourself to
`/etc/nixos/hosts/<hostname>/configuration.nix` and rebuild:

```nix
hardware.enableRedistributableFirmware = true;
```

It needs no `allowUnfree`. From v4.0.2-11 it is the default and the line is
redundant — harmless to keep, since it is only a default.

If the kernel log names a firmware file still missing after that, it is outside
the redistributable set: add `hardware.enableAllFirmware = true;` as well, which
*does* need `nixpkgs.config.allowUnfree` (already set in that file). That covers
Broadcom's `b43` and `brcm` blobs. Some Realtek cards — 8821CE, 8852BE — have no
in-tree driver at all and need an out-of-tree module instead; the doctor names
the right one for your device id.

### Why is there no swap partition, and can I hibernate?

There is no swap **partition** and there never was: `disk-config.nix` lays down
`@`, `@home`, `@nix`, `@log` and the snapshot subvolumes, and nothing else.

But an installed machine is not swapless. It runs **zram** — compressed swap in
RAM, capped at half of it — so `free -h` shows a swap device backed by
`/dev/zram0` rather than by the disk:

```sh
swapon --show
zramctl
```

zram is used instead of a swap file because a swap file on btrfs is a trap: it
needs its own `nodatacow` subvolume with the right attributes set *before* a
single byte is written, and getting it wrong means the kernel refuses to
`swapon` — usually on somebody else's machine. zram needs no disk layout at
all, so it behaves identically on a machine nixarchy partitioned and one it
did not.

**It is not hibernation.** Suspend-to-disk writes RAM to swap and then powers
off, so it needs *real* swap at least the size of RAM. zram lives in RAM, so
it cannot hold a copy of RAM. If you want to hibernate you need a swap file on
disk, and on btrfs it must be made this way:

```sh
sudo btrfs subvolume create /swap
sudo chattr +C /swap                  # nodatacow, BEFORE the file exists
sudo btrfs filesystem mkswapfile --size 32g /swap/swapfile
```

then in `/etc/nixos/hosts/<hostname>/configuration.nix`:

```nix
swapDevices = [ { device = "/swap/swapfile"; } ];
boot.resumeDevice = "/dev/disk/by-uuid/<the root filesystem's UUID>";
```

Size it at least your RAM. `boot.resumeDevice` is the *partition* holding the
file, not the file — and hibernation on an encrypted disk also needs the
initrd to unlock that device, which it already does for the root filesystem.

To turn zram off — because you added real swap, or you would rather not spend
the CPU on compression:

```nix
zramSwap.enable = false;
```

### Why can't I login or sudo with my password?

Upstream's answer is `faillock --reset`, and it applies here too: switch to a
TTY with `Ctrl+Alt+F2`, log in, and run
`faillock --reset --user <you>`.

If it is a password you set in your flake with `hashedPassword` or
`initialPassword`, a rebuild reapplies that value when
`users.mutableUsers = false`. That is a configuration, not a lockout.

### Steam, 1Password or Tailscale is installed but does not work

These are NixOS modules, not packages, and the app selection enables the
module (`programs.steam`, `programs._1password-gui`, `services.tailscale`).
If you added the package yourself to `environment.systemPackages` instead,
Steam has no FHS wrapper and 1Password has no setuid helper. Remove the
package and enable it through Install, or set the module option directly.

### Something crashed and I want to know why

`coredumpctl` has the dump. No public debuginfod serves nixpkgs builds, so
symbolizing it needs `nixseparatedebuginfod` locally; the `diagnose-crash`
agent skill nixarchy installs walks through it.

### 1Password authorization prompts

Unchanged from [upstream](https://omarchy.org/manual/troubleshooting/):
hardware acceleration must be on in 1Password's settings, and the app must
have been launched since boot.
