---
status: approved
issue: 1153
author: olafkfreund
---

# Intent: video backgrounds through owe, as upstream Omarchy ships them

## Problem

Upstream Omarchy now plays video and GIF backgrounds through
[omacom/owe](https://github.com/omacom/owe), a separate wallpaper engine. On
the `quattro` line, omacom/omarchy#12429 (merged 2026-09-21) made `owe` and
`owe-lockfeed` base packages, enabled `owed.service` for every user, and changed
the shell so it draws stills only and leaves the layer empty behind a video.

nixarchy cannot offer any of this:

- **It vendors v4.0.4,** which has no video backgrounds. `omarchy-theme-bg-next`
  lists `jpg jpeg png gif bmp webp` only, and the shell has no video path. The
  selection side came in omacom/omarchy#6792 (2026-09-06), also `quattro`-only.
  `quattro` is 622 commits ahead of v4.0.4 and has diverged from it.
- **owe is not in nixpkgs or in this repo.** It is C (meson) plus a Qt6 QML
  module (cmake), built against libmpv, ffmpeg, wayland, EGL and libsystemd.
- **Upstream's integration is written for Arch.** It points at
  `/usr/lib/systemd/user/owed.service` and `/usr/share/owe/10-owe-sync`, and it
  installs with `omarchy-pkg-add`. owe's own unit runs `%h/.local/bin/owed`.

The owner wants owe available and on by default.

## Proposed outcome

On a nixarchy machine:

1. A video (`mp4 m4v mov webm mkv avi`) or a GIF in a theme's backgrounds
   folder can be chosen like a still, and it plays as the desktop background
   on every monitor, decoded once.
2. It pauses when nothing can see it (fullscreen, lock, DPMS off, sleep), as
   upstream's pause policy says.
3. The lock screen shows the same video, muted, through owe's lock feed. When
   the feed is unavailable it shows a cached still frame instead.
4. The theme switch refreshes owe through the `theme-set` hook.
5. Stills behave exactly as they do today. While a still is showing, the
   renderer is not running.
6. `owe` (the CLI) is on `PATH`. `owe status` answers, and `owed` runs as a
   Home Manager user service.

## Affected users and systems

- Every installer-managed nixarchy machine: a new package, a new user service
  and a theme hook, plus a carried patch to the vendored shell if the backport
  route is chosen.
- `pkgs/`: a new `owe` package (binaries plus the `Owe.LockFeed` QML module).
  If backporting: a patch set on `pkgs/omarchy` for the shell's background,
  lock and picker files and the background scripts.
- `modules/home.nix`: the service, the hook and the QML import path for
  `omarchy-shell`.
- `tests/`: `options.nix` (both states) and `checks.session` (owed runs, and a
  video background is actually drawn).
- Docs: the manual page for backgrounds, and a Discussions announcement.

## Constraints

- **Mode A stays inert.** A configuration that only imports
  `nixosModules.nixarchy` gets no owe, no service and no hook.
- **Follow upstream's design, do not invent one.** Whatever nixarchy carries
  should match #12429 closely enough that the `quattro` bump deletes our copy
  rather than conflicting with it. Patches use `--replace-fail` (`pkgs/AGENTS.md`,
  "Patching upstream").
- **No posting upstream.** This is the owner's standing rule, so the licence
  question below is the owner's to settle.
- **The cache is public.** owe goes on the cachix allowlist only once its
  licence is settled, and only if its build cost justifies the space.
- **First-run must not enable NixOS units** (`pkgs/AGENTS.md`). The service
  comes from Home Manager with `wantedBy`, not from upstream's
  `enable-user-units.sh` line.
- **A blank desktop must be visible to a check.** Upstream's desktop has no
  fallback: with a video background and owed not running, the shell draws
  nothing. Under AGENTS.md §2, something has to be able to see that.

## Open questions

1. **Licence.** owe's repository has no LICENSE file. Its PKGBUILD says MIT,
   and upstream Omarchy ships it to every install. Is the PKGBUILD's
   declaration enough to package it here and serve it from the public cache,
   or should the owner ask the owe authors for a LICENSE file first? (I will
   not ask them; that is the owner's call.)
2. **Now, or with the `quattro` bump?**
   - *Backport now:* carry #6792's selection side and #12429's shell changes
     as a patch set on v4.0.4. Usable as soon as this lands. Cost: a large
     carried patch, re-applied at every v4.0.x bump and deleted at `quattro`.
     Both PRs touch files `quattro` has since changed further
     (`Background.qml` five more times, `LockView.qml` once).
   - *With the bump:* package owe now, behind an option, and turn it on in the
     same change that moves nixarchy to `quattro`. No carried shell patch, but
     nobody can use a video background until that bump.
3. **Audio.** Upstream plays a video's audio track through the default output.
   Keep that, or ship a default `~/.config/owe/config.toml` that mutes it?
4. **On by default, or installed with a switch?** Upstream makes owe a base
   package. The owe README still calls the project experimental ("use it at
   your own risk", v0.2.8). Match upstream exactly, or install it but leave
   `programs.nixarchy.owe.enable` off until it has run on real hardware here?
   GPU (VAAPI) decoding cannot be tested in a VM.

## Owner's answers (2026-10-02)

- **Question 2: backport now.** "Ready to use" on v4.0.4, carried as a patch
  set until the `quattro` bump deletes it.
- **Question 4: on by default,** as upstream ships it.
- **Questions 1 and 3** were not answered at approval. The spec proposes a
  default for each, and the spec approval settles them.
