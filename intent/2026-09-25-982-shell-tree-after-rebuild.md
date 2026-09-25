---
status: approved
issue: 982
author: olafkfreund
---

# Intent: a restarted shell should run the tree you just built

## Problem

After `nixos-rebuild switch`, the running Omarchy shell keeps reading the
**login-time** omarchy tree -- and restarting the shell does not change that.
Generated menu data only takes effect at the next re-login.

Seen on razer with #964's Ask-topic aliases: generation 2957's tree has
`"aliases":["slow",...]` on `trigger.ask.optimize`; the running session was on
an older tree without them, so typing "system slow" found nothing. The feature
was shipped, built, and invisible.

## The mechanism, read rather than inferred

`share/omarchy/bin/omarchy-restart-shell` already knows about this class. Its
line 8 reads the session's `OMARCHY_PATH` out of the user manager, under the
comment *"The user manager receives Hyprland's environment at session start."*
That value sets `CONFIG_DIR`, which is what **kills** the old shell.

Line 70 then relaunches through `hyprctl dispatch exec_cmd`. **Hyprland spawns
that child with its own environment**, fixed at login. Confirmed on this host:
Hyprland's `/proc/<pid>/environ` carries
`OMARCHY_PATH=/nix/store/rp5i87d4...-nixarchy-omarchy-tree`, and the running
shell has the same. So the careful read at line 8 is used for the kill and
discarded for the launch.

That is also why the issue's workaround fails: setting the variable in the
**systemd user manager** does not change an already-running Hyprland, so its
`exec_cmd` children are unaffected.

## Ours, though the script is upstream's

It is not in `pkgs/omarchy/nix-bin/`, so section 11 would normally route a fix
upstream. By the discriminator #963 established, the question is whether the bug
exists there.

It does not. On Arch `OMARCHY_PATH` is `/usr/share/omarchy`: one stable path,
identical before and after an upgrade, so inheriting the login-time value is
correct and free. **Our port made it a store path that moves on every rebuild.**

This is the third symptom of that single fact: #963 (IPC matched on a stale
path), this one, and the workaround already sitting at line 8 for a fourth.

## Proposed outcome

- After a rebuild, restarting the shell runs the current generation's tree --
  no re-login.
- Or, if that cannot be done safely, the user is **told** a re-login is needed,
  rather than getting a restart that silently changes nothing.
- Nothing is restarted on the user's behalf during activation.

## Affected users and systems

- Anyone who rebuilds while logged in, which is the ordinary way to use this
  and what `omarchy update` does.
- Every change to generated tree data: menu rows, aliases, seeded config.
  #961's aliases and #946's menu plugin both land here.
- `omarchy-restart-shell`, and possibly `omarchy-launch-shell`.

## Constraints

- **A patch here is re-applied at every source bump** (section 11), so it must
  be small and use `--replace-fail`, like #963's, so a bump that rewords the
  line fails the build rather than silently dropping the fix.
- **Do not restart the shell from activation.** A rebuild that kills the
  desktop under someone mid-task is worse than a stale menu, and upstream's own
  restart command exists precisely so the user chooses when.
- **The kill path must keep working.** Line 8's session read is correct for
  finding the *running* shell; only the launch is wrong. A fix that changes both
  can fail to kill the old one and leave two.
- Hyprland's environment cannot be rewritten from outside for an already-running
  instance. Any fix has to pass the value explicitly rather than hope to change
  what is inherited.

## Open questions

1. **Pass it, or resolve it at launch?**
   - **Pass it explicitly** in the `exec_cmd` string, using the path the script
     has already computed. One line, at the place that already did the work,
     and it changes no other caller.
   - **Resolve it in the launcher**: have `omarchy-launch-shell` read the
     current generation's tree itself rather than trusting its environment.
     Fixes every caller at once, including Hyprland keybinds, and is a bigger
     change to another file that may also be upstream's.

   I lean to **passing it explicitly**.

2. **Is `/run/current-system` the right source, or the user manager?** The
   script reads the user manager, which is what the issue's workaround
   manipulated -- and that was not enough for the *launch*, but may be exactly
   right once the value is passed through. To establish before the spec: does
   activation update the user manager's `OMARCHY_PATH` on a switch, or only at
   login?

## Not in scope

- Restarting the shell automatically on rebuild.
- #953's five-second kill timeout in the same script, which is upstream's.
- Anything about what the shell does once it has the right tree.
