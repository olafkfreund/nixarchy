---
name: nixos
description: >
  REQUIRED for installing, removing or updating software on this NixOS machine, and
  for any change outside ~/.config/ — system services, users, hardware, boot,
  networking, fonts, or Home Manager. Use when asked to install an app or package,
  enable a service or daemon, change a system setting, edit configuration.nix or a
  flake, run nixos-rebuild, roll back a broken system, search for a package or
  option, or explain why a change did not survive a reboot. Triggers: install,
  uninstall, add package, nixpkgs, nixos-rebuild, flake, generation, rollback,
  systemPackages, home-manager, apps.nix, nixarchy-apply, "make it permanent".
  For desktop appearance and Hyprland config, use the `nixarchy` skill instead.
---

# NixOS Skill

Make changes to this machine that **last**.

The single rule that governs everything below: **NixOS is declarative. A package
installed imperatively does not survive the next rebuild.** There is no
`apt install`, no `pacman -S`, no `pip install --user` that belongs in a system
change here. If a request would normally end in an install command, it ends in a
file edit and a rebuild instead.

## Decide Which Route to Take

Three routes exist on a Nixarchy machine. Pick the highest one that fits.

`nixarchy` with no arguments lists what this port adds; anything it does not own
falls through to `omarchy` unchanged, so `nixarchy theme set <name>` and
`omarchy theme set <name>` are the same command. The `nixarchy-*` binaries are
still there and still work — `nixarchy pkg add` and `nixarchy-pkg-add` are the
same thing.

| The request | Route |
|---|---|
| An app Nixarchy already knows about | **`nixarchy app enable <id>`**, then `nixarchy apply` |
| Any other package, service, or system setting | **`nixarchy-pkg-add <attr>`** for a plain package; otherwise **edit the flake**, then `nixos-rebuild switch` |
| A one-off, throwaway try — not a change to the machine | **`nix shell nixpkgs#<pkg>`** |

Never reach past route 1 for an app it covers: it writes the same file the Install
menu writes, so the menu and the flake stay in agreement.

**`nix-env -i` and `nix profile install` are not routes.** They create imperative
user state that no file records, that a rebuild does not reproduce, and that is
invisible to anyone reading the configuration. If you find yourself typing either,
the answer is route 2.

## Route 1: Apps Nixarchy Knows

Nixarchy maps the apps Omarchy's Install menu offers onto Nix. The selection lives
in one file, fully populated and entirely commented out:

```
~/.config/nixarchy/apps.nix
```

Enabling an app uncomments one line. Nothing is built until you apply.

```bash
nixarchy-app-enable brave        # uncomment the line
nixarchy-app-disable brave       # re-comment it
nixarchy-apply                   # copy the selection into the flake, then rebuild
```

`nixarchy-apply` does three things: prints what is enabled, copies
`~/.config/nixarchy/apps.nix` to `<flake>/nixarchy-apps.nix`, and offers to run
`nh os switch <flake>` (a front end to nixos-rebuild; no `sudo`, it elevates
itself).

**The copy is necessary and the import is the user's job.** A flake cannot read a
file outside its own tree, so the selection has to be copied in. Something in the
flake then has to import it:

```nix
imports = [ ./nixarchy-apps.nix ];   # path relative to the file you add it to
```

Without that line every app looks enabled, the rebuild runs to completion, and
nothing is installed. `nixarchy-apply` warns loudly when nothing imports the file —
**if you see that warning, fix it before doing anything else.** It is the single
most common reason a Nixarchy install "does nothing".

To find out which apps are mapped, and which of them you already have:

```bash
nix run github:olafkfreund/nixarchy#doctor
```

Some apps are not plain packages and are wired as NixOS modules instead — Steam
needs an FHS wrapper, 1Password a setuid helper, Tailscale a daemon, Firefox its
policy module. `nixarchy-app-enable` already knows which is which; that is why it
exists rather than a `systemPackages` line.

## Route 2: Add a Package, or Edit the Flake

For everything else. First, find where the configuration lives:

```bash
echo "${NIXARCHY_FLAKE:-/etc/nixos}"       # what Nixarchy's own commands use
```

`programs.nixarchy.flake` sets that. It is often not `/etc/nixos` — many people keep
their configuration in a git repo under `~`. Confirm before editing anything.

### Adding a package

Do not know the attribute name? `nixarchy-search` is an fzf picker over every
nixpkgs package, every NixOS option and the curated app list at once, with the
type, default and description in a preview pane. It routes what you pick to the
right writer, so it covers all three routes below:

```bash
nixarchy-search            # or the Install > Search menu row
nixarchy-search tailscale  # start with a query
```

The index is built from this system's own nixpkgs and options -- about a minute,
once per system generation -- so it never offers something this machine cannot
build.

For a plain package with no options to set, route 2 does the edit for you. It
validates the attribute against the system's own nixpkgs, appends it to
`~/.config/nixarchy/apps.nix` — the same file the Install menu writes — and
leaves the rebuild to `nixarchy-apply`, so menu picks and hand-added packages
build together:

```bash
nixarchy-pkg-add ripgrep jq
nixarchy-apply
```

It refuses an attribute nixpkgs does not have, and redirects to
`nixarchy-app-enable` for anything the curated list already covers as a module.

Editing the flake by hand is the same thing, and is what you want when the
package needs an override or belongs somewhere other than the machine-wide set:

```nix
environment.systemPackages = with pkgs; [
  ripgrep
  jq
];
```

For one user rather than the whole machine, and if Home Manager is in use:

```nix
home.packages = with pkgs; [ ripgrep ];
```

### Enabling a service

Prefer the module over the package almost every time. A package puts a binary on
`PATH`; the module also creates the unit, the user, the firewall hole and the state
directory.

```nix
services.tailscale.enable = true;
programs.steam.enable = true;
```

### Finding the right name

Guessing attribute names wastes rebuilds. Search first:

```bash
nix search nixpkgs ripgrep                 # packages
man configuration.nix                      # options, offline
```

Or use <https://search.nixos.org/packages> and <https://search.nixos.org/options>.
The package attribute and the command it installs often differ — `vscode` puts
`code` on `PATH`, `obs-studio` puts `obs`. Check `meta.mainProgram` when unsure:

```bash
nix eval --raw nixpkgs#vscode.meta.mainProgram
```

### Applying it

```bash
sudo nixos-rebuild switch --flake "${NIXARCHY_FLAKE:-/etc/nixos}"
```

Useful variants:

```bash
# Build and check it works, but do not make it the default at boot
sudo nixos-rebuild test --flake <flake>

# Build only — no activation. Safest way to check an edit evaluates
nixos-rebuild build --flake <flake>

# Make it the boot default without switching now
sudo nixos-rebuild boot --flake <flake>
```

**Prefer `build` or `test` while iterating**, and `switch` once it is right.

If the flake is a git repository, **Nix ignores untracked files**. A newly created
`.nix` file that has not been `git add`ed produces `path does not exist` or is
silently absent from the build. `git add` it before rebuilding.

## Route 3: Try Without Installing

For a one-off — checking whether a tool does what the user wants, running something
once:

```bash
nix shell nixpkgs#ripgrep       # a shell with it on PATH; leaves nothing behind
nix run nixpkgs#ripgrep -- --version
```

Say clearly that this is temporary. If the user wants to keep it, that is route 1 or 2.

## Updating

```bash
omarchy update      # nix flake update + nixos-rebuild switch, with a confirmation
```

Or by hand:

```bash
nix flake update --flake <flake>          # move every input forward
nix flake update nixpkgs --flake <flake>  # move just one
sudo nixos-rebuild switch --flake <flake>
```

`nix flake update` rewrites `flake.lock`, so the flake directory has to be writable
by the user running it. A root-owned `/etc/nixos` fails with a permission error on
the lock file.

## When Something Breaks

This is NixOS's best feature and the most under-used. **The previous working system
is still on disk.**

```bash
sudo nixos-rebuild --rollback switch      # back one generation, now
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Or reboot and pick an older generation from the boot menu. Nothing is lost by trying
a change.

To see what actually changed between two generations:

```bash
nix profile diff-closures --profile /nix/var/nix/profiles/system
```

That is the honest answer to "what did that update change?" and it is far better
evidence than a package log.

### Reading a failure

- **`error: attribute 'foo' missing`** — wrong package name. Search for the real one.
- **`error: The option 'services.foo' does not exist`** — wrong option path, or the module is not imported. Check <https://search.nixos.org/options>.
- **`error: path '/nix/store/...' does not exist` on a file you just created** — untracked in git. `git add` it.
- **`infinite recursion encountered`** — usually a `config` value used to compute something it also defines. Look for a self-reference.
- **unfree licence errors** — a single unfree package aborts the whole rebuild. Set `nixpkgs.config.allowUnfree = true;` deliberately, or drop the package.

## Rules

- **Read the file before editing it.** Configurations are personal; match the style and structure already there.
- **Never install imperatively** to "get it working now, declare it later". It will be forgotten, and it will vanish at the next rebuild while looking like it worked.
- **Show the user the diff before rebuilding.** A rebuild is fast to undo but slow to run; a wrong attribute name found by reading is cheaper than one found by building.
- **Do not run `nix flake update` as a fix.** It moves every input and changes far more than the problem at hand. Update one input, or none.
- **Do not garbage-collect to free space unless asked.** `nix-collect-garbage -d` deletes every old generation, which is exactly the rollback safety net above.
- **A rebuild needs `sudo`; evaluation does not.** Use `nixos-rebuild build` freely to check work without a password prompt.

## Example Requests

- "Install Brave" -> `nixarchy-app-enable brave && nixarchy-apply` (route 1)
- "Install ripgrep" -> `nixarchy-pkg-add ripgrep && nixarchy-apply` (route 2)
- "Enable Tailscale" -> `services.tailscale.enable = true;` — the module, not the package
- "Try out helix quickly" -> `nix shell nixpkgs#helix`, and say it is temporary
- "My package disappeared after reboot" -> it was installed imperatively; declare it properly
- "Update my system" -> `omarchy update`
- "That update broke my desktop" -> `sudo nixos-rebuild --rollback switch`, then diff the closures
- "Add a font" -> `fonts.packages = [ pkgs.<name> ];` — fonts are registered, not just installed
- "What changed in the last update?" -> `nix profile diff-closures --profile /nix/var/nix/profiles/system`
- "Change my wallpaper / theme / keybinding" -> NOT this skill. Use the `nixarchy` skill
