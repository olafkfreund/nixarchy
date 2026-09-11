---
title: nixarchy
layout: home
---

[Omarchy](https://omarchy.org) — the Hyprland desktop — vendored for NixOS, with
its menus rewired to Nix instead of pacman.

Omarchy 4.x is not a dotfiles repo, it is an application: 444 shell commands, a
QuickShell desktop shell, 22 themes, and Hyprland configured through the Lua API
introduced in 0.55. nixarchy packages that tree as a derivation and replaces the
parts that assume Arch, rather than reimplementing it in Nix.

Tracking an upstream release is a source bump, not a re-port.

> **nixarchy is in active development, and you should expect to hit problems.**
> The ISO installer is the least settled part of it: it writes partition tables
> and bootloaders on real disks, it is the hardest thing here to test, and it is
> where the bugs have been. Try it on a spare machine or a VM, and back up
> anything on the target disk.
>
> **If you already run NixOS, the flake route is the mature one.** Adding
> `nixarchy.nixosModules.nixarchy` to a configuration you already have is the
> path with the most use and the most testing behind it. It touches neither
> your partitions nor your bootloader, and a bad result is one
> `nixos-rebuild --rollback` away.
>
> Everything here is being worked on and tested continuously. Please
> [report what you hit](https://github.com/olafkfreund/nixarchy/issues) —
> `omarchy bug-report` collects the useful details for you.


## Install it on a blank machine

```
nix build github:olafkfreund/nixarchy#iso
sudo dd if=result/iso/nixarchy-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot it. No boot menu and no login prompt — the installer is what comes up. It
asks the questions Omarchy asks, in the same order, encrypts the disk unless you
opt out, and is done in a few minutes.

![Installing nixarchy](img/installer/install.gif)

What you end up with is **a flake you own** at `/etc/nixos`: a git repository
holding the disk layout, the configuration and your app selection. A rebuild
straight after installing builds nothing, because everything the installer did
is written there rather than done behind it.

**The ISO carries its own closure, so an install needs no network.** It is
checked with no network device present at all: 2,221 store paths copied from
the medium, zero fetched, nothing built. A machine with no wifi driver yet, or
no cable to hand, still installs — [see the manual](manual/getting-started) for
the remaining limits. Already running NixOS? Then you want the flake, not the
ISO, and that is on the same page.

## Search everything, install declaratively

Omarchy's Install menu offers 64 applications. **Install ▸ Search** offers the
rest of NixOS — one fuzzy picker over **137,599 rows**: every nixpkgs package,
every NixOS option, and the app selection, with each entry's type, default and
documentation in a preview pane.

```
nixarchy > tailscale
app  tailscale                          Tailscale (Service)
pkg  tailscale                          Node agent for Tailscale, a mesh VPN …
opt  services.tailscale.enable          Whether to enable Tailscale client daemon
opt  services.tailscale.authKeyFile     A file containing the auth key …
```

The three kinds are not interchangeable, and the rows say so: the app row gets
you `services.tailscale` with its daemon, the package row gets you the CLI and
nothing running. Picking routes to whichever writer is right — an app is
enabled as an app, a package is validated and appended, an option is written as
a line of its own. Booleans and enums get a value picker; anything more
complicated is written commented out with its type and docs beside it, because
an option's value is arbitrary Nix and a form that pretended otherwise would
write plausible-looking wrong configuration.

Nothing is built until you apply. The index comes from *this machine's* nixpkgs
and options rather than from search.nixos.org, so it can never offer something
the machine will then refuse to build.

This is the whole model in twenty seconds — a pick becomes a line in a file
you own, and only then a rebuild:

![nixarchy-app-enable helix writes a declaration into ~/.config/nixarchy/apps.nix — grep shows the uncommented line — then nixarchy-apply copies it into the flake and offers the rebuild](img/features/install.gif)

See **[other packages](manual/other-packages)** for the whole flow.

## The binary you just downloaded runs

NixOS deliberately has no `/usr/lib`, so a prebuilt Linux binary — a pip
wheel with compiled code, an Electron app, a game — normally dies with
`libGL.so.1: cannot open shared object file`. nixarchy turns the escape
hatches on by default:

- **[nix-ld](https://github.com/nix-community/nix-ld)**, loaded with a
  curated set of what desktop downloads actually link against — `libGL`, the
  X and Wayland client stacks, fontconfig, NSS for Electron, ALSA, ffmpeg —
  so most prebuilt binaries simply run.
- **envfs** mounts `/bin` and `/usr/bin`, so a script whose shebang says
  `#!/usr/bin/python3` runs instead of reporting "No such file or directory"
  about a file you are looking at.
- **AppImages are double-clickable**: binfmt registration runs them directly,
  no `appimage-run` incantation to know about.

And when something still fails, `nixarchy-doctor <binary>` runs the loader's
own resolution against that file and names the missing library and the
`programs.nix-ld.libraries` line that supplies it — instead of leaving you
to decode `cannot open shared object file` yourself.

See **[Python](manual/python)** — the page is named for where people hit
this first, but the loader story covers Node, Electron and games too.

## An agent that knows this machine

Omarchy symlinks its agent skills into every harness's skill directory. Upstream
ships one, written for Arch; nixarchy ships thirteen, written for NixOS — the
desktop, packages, GPUs, services, secrets, performance, security, log triage,
Android, and getting the configuration into git.

That matters more than it sounds. A model asked how to install a package on NixOS
will confidently invent an answer; the same model handed the `nixos` skill routes
to `nixarchy-pkg-add` and a rebuild. The skills were written against the modules
on disk rather than from memory, which is how they caught two options current
models still write and that no longer exist.

**Menu ▸ Trigger ▸ Ask** turns them into ten things you can click — *What's
wrong?*, *Make it faster*, *Am I exposed?*, *Disk is full* — each routed to the
skill that answers it, through whichever agent you have chosen.

![The Ask menu](img/desktop/menu-ask.jpg)

```nix
programs.nixarchy.localAi.enable = true;
```

runs the whole thing locally against Ollama, with the accelerator derived from
the GPU your configuration already declares. It refuses to build without one,
and the refusal explains why with the measurements behind it.

See **[the AI page](manual/ai)**.

## → [The nixarchy manual](manual/)

What is different here, and only that. Omarchy's manual covers the desktop; this
one covers the port — packages, updates, rollback, the firewall, the agent
skills, and the NixOS philosophy underneath all of it.

New to NixOS? Start with
**[the philosophy](manual/philosophy)** and **[updating NixOS](manual/updating-nixos)**.

## Get this machine back on new hardware

`nixarchy reinstall iso` builds a bootable image **from this machine's own
configuration**. Boot it on a new laptop and you get this system back --
packages, desktop, services, settings -- with nothing downloaded and nothing
compiled, because the closure is on the medium.

It is the only one of the five ways back that survives losing the disk: a
generation covers a bad change, a snapshot covers a deleted file, and two git
repos cover your dotfiles and your configuration.

**It is not a backup, and the name says so on purpose.** It carries your
system, not your files -- no `/home`, no browser profiles, no service state --
and booting it erases the target disk. The trap that names avoids is somebody
losing a disk, booting the thing they called a backup, and getting a clean
machine with none of their photographs.

See **[a reinstall image of this machine](manual/reinstall-image)**.

## Where this has got to

Four features finished recently, and each is here because it is *checked*, not
because it was written:

**An install that needs no network.** The ISO carries its own closure instead
of downloading one. Proven with no network device present at all — 2,221 store
paths copied from the medium, zero fetched, nothing built. This was the last
thing standing between the installer and a machine whose wifi driver is not
loaded yet.

**See a change before you live in it.** `nixarchy-preview` boots your edited
configuration in a VM and shows it to you, and the machine you are sitting at
is untouched until you decide. It is not `build-vm`, which is one command and
gives you a black screen — qemu's virgl path hands out no usable EGLConfig, so
the feature is a VM-only module carrying software-GL fallbacks that never reach
your real machine. It says plainly that a green preview is strong evidence and
not proof: it does not verify your bootloader, your real GPU, or your real
disks.

**Your phone, on the desktop.** scrcpy and Waydroid in the catalogues, and a
pairing helper for the part that actually defeats people — pairing over Wi-Fi,
where Android wants two different ports, regenerates one of them every time you
open the dialog, and gives you a code that expires in seconds.
Discovery goes through avahi, because nixpkgs builds `android-tools` without an
mDNS backend and the command every tutorial names answers *"mdns is not
supported by this version of adb"*.

**The session, from somewhere else.** A headless output, an RDP service and its
firewall hole, and authentication that does not quietly fall back to a shared
secret.

**Stable or unstable, your choice.** *Update ▸ Channel* offers it the way
Omarchy does, and moves nixpkgs and home-manager together — the two are
developed as a pair and a mismatch is a combination neither project supports.
You can also take a single package from the other channel without moving the
machine.

It was sequenced deliberately, and the reason is worth stating: nixos-26.05
ships a version of the desktop shell whose lockscreen can leave a machine blank
with nowhere to type a password. That is fixed *before* anyone is offered the
choice that would hand it to them. And the page says the uncomfortable part
plainly — "stable" sounds safer and here it is **less tested**, because nixarchy
is developed against unstable.

See **[stable or unstable](manual/channels)**.

### What is being worked on now

The package picker remade, running an application once without installing it,
and a network variant of the reinstall image.

The [board](https://github.com/users/olafkfreund/projects/9) is public, and its
*Shipped* view is the honest answer to "is this thing alive".

## Elsewhere

| Where | What is there |
|---|---|
| [Source and README](https://github.com/olafkfreund/nixarchy) | installation, module options, design notes, what is left |
| [Omarchy's own manual](https://omarchy.org/manual/) | the desktop itself — 38 of its 51 pages are true here unchanged |
| [Issues](https://github.com/olafkfreund/nixarchy/issues) and the [board](https://github.com/users/olafkfreund/projects/9) | what is in flight, what is waiting, and what each feature has left — public |
