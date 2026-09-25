---
status: approved
issue: 948
author: olafkfreund
---

# Intent: display text size says what to change, instead of failing at a symlink

## Problem

`omarchy display text size 16` prints:

```
sed: couldn't open temporary file /nix/store/sedXXXXXX: Read-only file system
```

and the terminal font does not change. The shell and GTK parts still apply, so
the user gets a partial result and an error they cannot act on.

`share/omarchy/bin/omarchy-display-text-size:140,154,159` edits the terminal
configs in place:

```sh
sed -i -E "s/^size[[:space:]]*=.*/size = $pt/" ~/.config/alacritty/alacritty.toml
sed -i -E "s/^font-size = .*/font-size = $pt/"  ~/.config/ghostty/config
sed -i -E "s/(:size=)[0-9.]+/\1$pt/"            ~/.config/foot/foot.ini
```

## Half of this is ours and half is upstream's, and the test is #963's

`omarchy-display-text-size` is upstream's script -- not in
`pkgs/omarchy/nix-bin/` -- so section 11 would normally route a fix upstream. The
discriminator #963 established tonight is not who owns the file but **whether
the bug exists upstream**:

**The `sed -i` failure is ours.** Measured on this machine:

```
alacritty.toml: SYMLINK -> /nix/store/46c409cxvc80f...
config:         SYMLINK -> /nix/store/46c409cxvc80f...
foot.ini:       SYMLINK -> /nix/store/46c409cxvc80f...
```

All three are Home Manager symlinks into the store. On Arch they are ordinary
files in `$HOME` and `sed -i` works. **Our port made them read-only symlinks**,
exactly as it made `OMARCHY_PATH` unstable for #963. Upstream has no bug to fix.

**The `reset` half is upstream's.** `omarchy display text size reset` deletes
only the `base-size` line and leaves a `shell.toml` containing `[font]` and
nothing else, where no file existed before. That happens identically on Arch;
nothing about NixOS causes it. Out of scope here, and not filed anywhere
unprompted (section 11).

**And upstream already half-knows.** The kitty branch at `:147` uses
`sed --follow-symlinks -i` where the other three do not -- so somebody hit a
symlink once. It does not help here: following the link writes to the store
target, which is equally read-only.

## Proposed outcome

- Running `omarchy display text size <n>` on a machine whose terminal configs
  are declaratively managed **says so**, names the option to change, and does
  not print a `sed` error.
- The shell and GTK parts keep working, as they do today.
- A machine whose configs are ordinary files -- someone who opted out of the
  seeding -- keeps today's behaviour exactly.

## Affected users and systems

- Every nixarchy machine where the terminal configs come from Home Manager,
  which is the default.
- `pkgs/omarchy/default.nix` (the patch) and whatever names the option a user
  should set instead.

## Constraints

- **`--replace-fail`**, per `pkgs/AGENTS.md`: an Omarchy bump that rewords one
  of those lines must fail the build rather than silently restore the broken
  edit. This is the mechanism #963 used for the same reason.
- **Three lines, three different sed expressions.** A single replacement will
  not cover them; either each is patched, or the guard goes somewhere they all
  pass through.
- **Do not "fix" it by writing a real file over the symlink.** `sed -i` without
  `--follow-symlinks` would replace the link with a regular file, which appears
  to work and quietly takes the file out of Home Manager's management -- the
  next rebuild then fights it. That is a worse failure than the error.

## Open questions

1. **What should it do instead of editing?** Two shapes:
   - **Skip and explain** -- detect a store symlink, print the declarative
     option to set, carry on with shell and GTK. Smallest, honest, and leaves
     the user a manual step.
   - **Make the size an option** nixarchy renders into the seeded configs, so
     the menu row writes it declaratively and a rebuild applies it. Much bigger,
     and it is the NixOS-shaped answer rather than a patch over an Arch one.

   I lean to **skip and explain**, because it is proportionate to a font size
   and because the second is really a feature request wearing a bug's clothes.

2. **Where does the guard go?** Patching three `sed -i` lines separately is
   three `--replace-fail` needles that a bump can break independently. A single
   guard early in `set_terminal_size` is one needle and one place to read, but
   it is a larger patch and further from upstream's text.

## Not in scope

- The `reset` behaviour, which is upstream's.
- `#953`'s `timeout 5 quickshell kill`, which is also upstream's: its own
  evidence is a machine with 20+ plugins, and an Arch machine with 20 plugins
  races the same way. Nothing about the Nix port makes teardown slower.
