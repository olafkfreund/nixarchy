---
title: nixarchy's Plugins
---

# nixarchy's plugins

Omarchy's desktop is a Quickshell shell, and a shell plugin is a panel, a bar
widget or a menu that lives inside it. Most of what nixarchy adds to Omarchy is
a NixOS answer to an Arch habit, and for a while each answer was a floating
terminal: an `fzf` picker for packages, `distrobox` commands for boxes,
`nixarchy vm` for sandboxes. These plugins put those jobs back where the rest of
the desktop already is: a chord and a list, keyboard-first, in the shell's own
look.

Some are **on by default**: installed with nixarchy and turned on at your first
login. Others are on their way, and one stays **opt-in** on purpose. Each entry
below says which. Turning one on happens *once*, so a plugin you switch off in
**Setup → Plugins** stays off. [Configuring nixarchy](configuration#nixarchys-own-plugins)
covers how to stop nixarchy installing one at all.

The keys below (Super+Alt+…) are seeded into `~/.config/hypr/bindings.lua` on
**new** installs. nixarchy never edits that file afterwards, so on an existing
machine use the menu row, or copy the line from a fresh install.

| Plugin | What it's for | Status | Open it |
|---|---|---|---|
| [Package manager](#package-manager) | apps, services, packages and options | **on by default** | Install ▸ Packages · Super+Alt+N |
| [Podman](#podman) | containers, images, volumes, networks | **on wherever podman is** | Apps ▸ Podman · Super+Alt+O |
| [GitLab pipelines](#gitlab-pipelines) | CI for every project you belong to | **on by default** | Apps ▸ GitLab Pipelines · Super+Alt+P |
| [Herdr sessions](#herdr-sessions) | your herdr sessions and their agents | **on by default** | bar (right) · Apps ▸ Herdr · Super+Alt+H |
| [MicroVMs](#microvms) | disposable and permanent VMs, one list | **on by default** | Trigger ▸ Sandbox · Super+Alt+V |
| [Distrobox](#distrobox) | boxes, created from nixarchy's templates | **on wherever Boxes are** | Trigger ▸ Boxes · Super+Alt+D |
| [GitHub Actions](#github-actions) | workflow runs, jobs and steps | coming | — |
| [ai-mirror](#ai-mirror) | let an agent use your real desktop, and stop it | coming | — |
| [Voice](#voice) | operate the desktop by talking to it | **opt-in**, coming | — |

## Package manager

[nixarchy-pkg](https://github.com/olafkfreund/nixarchy-pkg) · [its own site](https://olafkfreund.github.io/nixarchy-pkg/)

**What it solves.** On NixOS you don't `pacman -S` a package; it goes into your
configuration and a rebuild builds it. Before this panel, that meant a floating
terminal and an `fzf` picker, or opening `~/.config/nixarchy/apps.nix` and
finding the right commented-out line. Every other surface on the desktop is a
chord and a list, and now so is this.

**What it does.** Search nixpkgs, turn curated apps and services on, add any
package, and set NixOS options through a form. Everything is written to the
same files nixarchy's own commands write, then applied with one key. The
rebuild asks for your password through the Omarchy dialog.

![The package manager: switching tabs, then filtering the Apps tab to one app and the line it writes](../img/plugins/pkg.gif)

![The package manager's Apps tab: curated apps and services, with what each one turns on](../img/plugins/pkg-apps.jpg)

![Searching nixpkgs for a package](../img/plugins/pkg-search.jpg)

![Searching NixOS options, then setting one through a form](../img/plugins/pkg-options.jpg)

## Podman

[nixarchy-podman](https://github.com/olafkfreund/nixarchy-podman) · [its own site](https://olafkfreund.github.io/nixarchy-podman/)

**What it solves.** Looking after rootless containers otherwise means a
terminal, `podman ps`, and remembering the flags. This keeps the everyday work
on the keyboard, without opening a shell.

**What it does.** Containers, images, volumes and networks on four tabs.
Start, stop and restart; follow logs; open a shell in a container; remove and
prune, with a confirmation. The bar glyph shows when something needs
attention.

**When it's there.** It follows podman, not nixarchy. It comes on with the
**podman** row in the Services catalogue, or with [Boxes](boxes), and is absent
where podman is off. nixarchy's container engine is still rootless Docker, so
`docker` keeps meaning Docker.

![The Podman panel: moving through the demo containers, then filtering to the shop ones](../img/plugins/podman.gif)

![The Podman panel's Containers tab: three of four running, one needing attention](../img/plugins/podman-containers.jpg)

## GitLab pipelines

[nixarchy-gltui](https://github.com/olafkfreund/nixarchy-gltui)

**What it solves.** Checking CI across many projects means a browser tab per
project. This is one popup: every project you are a member of, nested groups
included, with running pipelines first.

**What it does.** Projects → pipelines → stages → jobs, with no buttons, no
background daemon and no stored token. It uses `glab`, which nixarchy installs
with it. Run `glab auth login` once; until you do, the panel says so and stops
polling.

## Herdr sessions

[nixarchy-herdr](https://github.com/olafkfreund/nixarchy-herdr)

**What it solves.** Coding agents run inside [herdr](https://github.com/ogulcancelik/herdr)
sessions, and without this you find out that one is waiting for you only by
switching to its terminal. The bar tells you instead.

**What it does.** Your herdr sessions and the agents inside them, across
machines, not just this one. You see who is working, who is done, and who
**needs you**. Open a session, start a new one, or send an agent a prompt from
the popup. `herdr` itself comes with it from nixpkgs, so update it through
nixpkgs (`herdr update` cannot write to the Nix store), or put your own build
ahead of it on `PATH`.

![The herdr popup: three sessions, one agent needing you, two done](../img/plugins/herdr-sessions.jpg)

## MicroVMs

[nixarchy-microvm](https://github.com/olafkfreund/nixarchy-microvm) · [its own site](https://olafkfreund.github.io/nixarchy-microvm/)

**What it solves.** nixarchy has two kinds of VM: disposable [sandboxes](sandboxes)
from `nixarchy vm`, and permanent machines you declare in your configuration.
They lived in two places. This puts both in one list.

**What it does.** Create a VM from a template, run it in the background and
attach to its console later, stop it, or remove it. There's optional help from
your AI agent to fill in the create form. It is **Trigger ▸ Sandbox** now,
and `nixarchy vm` is still there in a terminal.

![The MicroVMs panel: two disposable demo VMs, filtered to one](../img/plugins/microvm.gif)

![The MicroVMs panel: disposable and permanent VMs in one list](../img/plugins/microvm-panel.jpg)

## Distrobox

[nixarchy-distrobox](https://github.com/olafkfreund/nixarchy-distrobox) · [its own site](https://olafkfreund.github.io/nixarchy-distrobox/)

**What it solves.** [Boxes](boxes) are for software NixOS will not run, and
looking after them meant remembering `distrobox` subcommands. A multi-minute
image pull or upgrade also tied up a terminal.

**What it does.** Every box with its image and home directory. Enter one in a
terminal; start, stop, restart, upgrade or delete it. Create a box from a form,
and watch create and upgrade stream into the panel. It is **Trigger ▸ Boxes**
wherever [Boxes](boxes) are on, and its templates are nixarchy's own, from
`/etc/nixarchy/box-templates.ini`.

![The Distrobox panel: two demo boxes, filtered to one](../img/plugins/distrobox.gif)

![The Distrobox panel: one box running, one exited, one created](../img/plugins/distrobox-popup.jpg)

## GitHub Actions

[nixarchy-ghtui](https://github.com/olafkfreund/nixarchy-ghtui) · **coming**

The GitHub counterpart of [GitLab pipelines](#gitlab-pipelines): repositories →
workflow runs → jobs → steps, with running workflows first, through `gh`. It
ships on by default once its licence is in place.

## ai-mirror

[ai-mirror](https://github.com/olafkfreund/ai-mirror) · **coming**

**What it solves.** A coding agent can drive a browser or a terminal, but not
the dialog, the drag or the unlabelled button on your real desktop. ai-mirror
gives an agent eyes and hands on your actual session, and takes them back
with one keypress.

**What it does.** A small MCP server plus a bar mark. The mark turns red while
an agent is in control, and **Super+Shift+Escape** revokes control at any
moment. When it ships in nixarchy it is installed, but **no agent is connected
to it automatically**, and an agent will not take control without you saying
yes first.

**[Watch the nixarchy desktop showcase](https://github.com/olafkfreund/ai-mirror/releases/download/demo-2026-09-18/nixarchy-desktop-showcase.mp4)**, recorded by an agent through ai-mirror.

## Voice

[nixarchy-voice](https://github.com/olafkfreund/nixarchy-voice) · [its own site](https://olafkfreund.github.io/nixarchy-voice/)
· **opt-in, coming**

**What it solves.** Operating the desktop by talking to it. It turns voice into
actions, not only text; [dictation](ai) (Voxtype) stays for typing.

**What it does.** A wake word or toggle key is heard locally, whisper.cpp
transcribes it on your CPU, a model you have signed in to answers, and a local
voice speaks the reply.

**Why it's opt-in.** It needs a model account, it sends what you ask about
(including screen and clipboard content) to that model, and it is about 1 GiB
with its speech models. So it is not in the default install. A **Set up voice**
menu row installs it and asks which backend to use. Notification logging, the
wake word and desktop control all start off.
