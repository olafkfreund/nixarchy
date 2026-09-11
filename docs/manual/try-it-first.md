---
title: Try It First
---

# Try It First

`nixarchy try <name>` runs an application once, to see whether you want it,
without adding it to your configuration. Nothing is written to
`~/.config/nixarchy/apps.nix`, nothing is rebuilt, and when the app exits
your system is configured exactly as it was.

It runs from the system's own pinned nixpkgs -- the same tree
`nixarchy-apply` installs from -- so what you try is exactly what installing
would deliver. A bare `nix run nixpkgs#name` does not give you that: it
resolves the global flake registry to whatever nixpkgs-unstable is today,
a version this machine has never seen.

There are two ways in:

- **`nixarchy try <name>`** in a terminal.
- **Install ▸ Search**, then `ctrl-t` on a package or app row. Enter still
  queues the selection for install; `ctrl-t` runs it now instead, in the
  same terminal the picker is in. The rows that can be tried say so in
  their preview.

## What it is not

**Not a sandbox.** This is the thing to be clearest about: `try` runs the
same code installing would, with your full user privileges -- your home
directory, your network, your session. The only thing it spares you is the
commitment. For code you do not *trust*, the answer is a
[sandbox](sandboxes): `nixarchy vm` boots a disposable NixOS with real
isolation. `try` is for an app you would happily install and are just not
sure you want.

**Not gone when it exits.** The package is downloaded into `/nix/store`
and stays there until garbage collection. A tried package has no
garbage-collection root, so it is pure garbage the moment you close the
terminal -- nothing references it, and collecting it can never cost you a
rollback.

On a machine the installer built, that collection is automatic: the Nix
daemon collects when free space falls below 5 GiB, which is the case this
setting exists for. You can also do it now, and it is the same operation:

```sh
sudo nix-collect-garbage
```

If you added nixarchy to a machine you already run, none of this is turned on
for you -- your own collection policy stands, and the command above is the
manual version.

**Not installed.** No launcher entry is created -- nothing writes a
`.desktop` file -- and the app runs in the terminal you launched it from.
Close the terminal and it goes with it. If it should survive that, that
is what installing is for.

## What can be tried

nixpkgs packages, and the apps in the catalogue that are a package
underneath. An app that is really a NixOS module -- firefox, docker --
has no single program to run; enabling it configures the system, which
only a rebuild can do. Flatpaks likewise have no package attribute to
run. `nixarchy try` says so rather than guessing at something to
execute, and the picker's `ctrl-t` gives the same answer.

## Keeping it

Install it the way you always would: pick it with enter in
**Install ▸ Search**, or `nixarchy-pkg-add <name>`, then
`nixarchy-apply`. Because `try` ran the pinned tree, the version you
tried is the version that installs.
