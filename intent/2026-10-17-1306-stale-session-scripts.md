---
status: draft
issue: 1306
author: olafkfreund
---

# Intent: After a switch, the menu and the scripts it runs come from one generation

## Problem

A desktop session fixes `OMARCHY_PATH` and its `PATH` at login. The session
launcher (`modules/nixos.nix:132`) and `environment.sessionVariables`
(`:1359`) both bake in that generation's `nixarchy-omarchy-tree`. A system
switch does not change them. But the menu reads its rows from
`/etc/nixarchy/omarchy-menu.jsonc`, which the switch does update. So after a
switch, a running session pairs new rows with old scripts until the user logs
out and back in.

The evidence is on #1306. A session from 2026-10-14 still had `OMARCHY_PATH`
at the old tree (`zlhw6r3r…`) while the system's tree was `rla9km5s…`:

- `omarchy-channel-current` printed `dev`, because the old script ran. The new
  one (#1291) prints `stable`.
- Rows calling `nixarchy-channel --current` got the old script's usage text
  instead of an answer.

Nothing tells the user to log in again. The menu review behind #1301–#1305
was misled by this too: it audited the stale tree.

## Proposed outcome

After a switch, a running session does one of two things. Either it runs the
new generation's scripts for the menu's rows, or it tells the user once,
plainly, that they need to log in again and why. A row never runs a script
from a different generation than its own without anything saying so.

## Affected users and systems

- Everyone on the Omarchy session who switches without logging out. That
  includes `nixarchy-apply`, the menu's own Update rows, and the edge
  channel's updates.
- `modules/nixos.nix`: the session launcher and `sessionVariables`.
- `modules/home.nix`: the `OMARCHY_PATH` exports in user scripts (`:514-516`).
- `/etc/nixarchy/omarchy-menu.jsonc`, and how the shell reads it.
- `docs/manual/plugins.md:278`. It tells users to log in again after one
  specific switch only.

## Constraints

- **Mode A.** Nothing changes for a configuration that does not use the
  Omarchy session.
- **Never pull the session out from under the user.** Anything that reloads
  the shell or compositor is either something the shell already does, or the
  user's own choice.
- **The check varies the generation between login and menu use (§3).** A
  check that logs in after the switch cannot see this bug.
- **Frequent switches.** The edge channel switches more often, and whatever
  is chosen must hold for that.

## Open questions

1. **Fix, or tell?**
   - (a) Point the session at a stable path the switch updates, such as
     `/run/current-system/sw/share/omarchy` or an `/etc/nixarchy/tree` link,
     so new processes resolve the new tree.
   - (b) Keep the pinned path, and have the post-switch path notify once that
     a re-login is needed.
   - (c) Both: (a) for scripts, and (b) for what cannot follow, such as the
     running shell's own QML.
2. **The running shell's QML.** (a) only helps processes started after the
   switch. Does the shell need a reload to pick up new plugin code, and does
   the menu already re-read its rows?
3. **Does anything rely on `OMARCHY_PATH` staying the same?** For example,
   store garbage-collection roots, or a script that compares paths.
