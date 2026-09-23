---
status: approved
issue: 919
author: olafkfreund
---

# Intent: an apply started from a panel tells you how it ended

## Problem

Applying from a shell panel works and then appears not to.

A panel that runs `nixarchy-apply` streams the build log. When the switch
activates, the session reloads its Hyprland configuration — the journal shows
uwsm and Xwayland recompiling the keymap, `xkbcomp` runs, the screen blanks for
a frame — and **every open shell panel is closed**. The apply itself finishes.
Its result line never appears, because the thing that was going to print it no
longer exists.

What the user sees is the log running, a black frame, and then the wallpaper.
Whether the rebuild succeeded, failed, or is still going is not on screen
anywhere, and the only way to find out is to reopen the panel and infer it.

This is not one panel's bug. It is the shared `nixarchy-apply` → `nh os switch`
path, so it reaches nixarchy-flatsnap's `— applied —`, nixarchy-pkg's `apply()`,
and anything else that grows an apply button later. It was found on razer while
recording the Flatpak & Snap panel, doing the ordinary thing the panel exists
for.

The failure is worst in the case that matters most. An apply that changes
nothing does not reload, so the panel stays open and says it worked — and an
apply that changes a lot is the one that vanishes. **The more consequential the
change, the less likely you are to be told how it went.**

## Proposed outcome

After applying from a panel, the user learns the outcome without having to know
that a reload ate the panel, and without having to reconstruct it from
`journalctl`.

Observable:

- an apply that triggers a session reload still reports success or failure to
  the user, on screen, after the reload;
- an apply that fails is at least as visible as one that succeeds — a silent
  failure here is worse than the current silence, because the log said
  `Activating configuration` before it disappeared;
- an apply that changes nothing keeps behaving as it does today, since nothing
  is wrong with that path;
- whatever carries the result is available to any panel, not written a second
  time in each one.

## Affected users and systems

- **Anyone applying from a panel**, which is now the default route: Install ▸
  Apply changes, the Flatpak & Snap panel, the Package manager panel.
- `pkgs/rebuild-panel/` — already models a rebuild as a systemd unit it reads
  rather than a process it owns, which is the shape this problem wants.
- `modules/apps.nix` — `nixarchy-apply`, `nixarchy-rebuild-state`, and the
  `--detach` path from #765.
- The panels in their own repositories (`nixarchy-flatsnap`, `nixarchy-pkg`),
  which is where the duplicated result lines live today. A fix that needs each
  of them changed is a worse fix than one that does not.
- Real hardware only. No VM in this repository has a session that reloads
  Hyprland mid-apply, which is why CI never saw it.

## Constraints

- **Must not make the rebuild itself less reliable.** #765 deliberately moved
  the rebuild into a user unit so a closed window cannot kill it. Nothing here
  may put the outcome back inside the window's lifetime.
- **Must not offer a cancel.** `SIGTERM` to `nh` can land mid-activation;
  `modules/AGENTS.md` already records why the rebuild panel has no cancel verb,
  and the same reasoning holds for anything that reopens.
- **Must not require every panel to be changed.** A result each panel has to
  remember to display is the hand-maintained list §4 warns about, one repository
  at a time.
- **Should not fight the reload.** Whether the session needs to reload on
  activation is a real question, but suppressing it is a change to how every
  rebuild behaves on every machine, not a fix for a missing message.
- Mode A must gain nothing: someone importing `nixosModules.nixarchy` into
  their own configuration is not running these panels.

## Open questions

1. **Where should the result live?** `nixarchy-apply --detach` already runs as
   the `nixarchy-rebuild` user unit, and `nixarchy-rebuild-state` already maps
   its `SubState`/`Result`/`ExecMainStatus` to idle/running/succeeded/failed.
   That is a result that survives the panel, today, with no new mechanism —
   should this simply be "panels use the detached path and read that", or is a
   durable record of *the last apply* needed as well?

2. **Who shows it, and when?** Three shapes, and this is the decision the spec
   turns on:
   - the **rebuild panel** reopens itself after a reload and reports — one
     place, but it means a panel that summons itself, which nothing here does;
   - a **notification**, which survives a compositor reload and needs no panel
     at all — simplest, and the weakest at conveying a build log;
   - the **bar widget** already in `pkgs/rebuild-panel/` grows a settled state
     the user can click — it is already `visible` when a rebuild is running or
     failed, so this may be mostly true already.

3. **Is the reload itself in scope?** The issue's third direction is to find
   which activation step reloads Hyprland and whether it needs to. That is a
   different problem with a different blast radius. I would rather answer this
   issue without touching it, and file what I learn separately — but if you
   want the reload investigated as part of this, the spec has to be bigger.

4. **Does a failed apply need to be louder than a successful one?** Today both
   are equally invisible. A notification for both is symmetrical; a
   notification only on failure is quieter but hides the confirmation the user
   is actually waiting for.
