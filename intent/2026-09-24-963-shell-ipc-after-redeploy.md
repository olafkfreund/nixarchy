---
status: approved
issue: 963
author: olafkfreund
---

# Intent: shell IPC should find the shell that is running, not the one we just built

## Problem

After a redeploy, `omarchy-shell` IPC calls miss the shell that is still
running, until a re-login or a shell restart. `omarchy-shell shell toggle
<plugin-id> '{}'` is what plugin keybinds run -- Super+Alt+U among them -- so
the symptom is a keybind that silently does nothing on a machine that looks
fine.

The cause, at `share/omarchy/bin/omarchy-shell:59`:

```sh
output=$(timeout --kill-after=1s "$ipc_timeout" qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@" ...)
```

It finds the running instance **by config path**. The caller has the new
`OMARCHY_PATH`; the running shell was started from the old one; the match fails.

## This is ours, and the script is upstream's

Both halves of that sentence matter, because the routing decision looks
obvious and is wrong.

`omarchy-shell` is **not** in `pkgs/omarchy/nix-bin/` -- it is upstream's, and
nixarchy does not patch it today. Under CLAUDE.md section 11 that would normally
mean the fix belongs upstream and a patch carried here is re-applied at every
source bump.

**But there is no bug upstream.** On Arch, `OMARCHY_PATH` is
`/usr/share/omarchy`: one stable path, the same before and after an upgrade, so
matching on it is correct and cheap. On NixOS it is `cfg.tree`
(`modules/nixos.nix:1158`) -- a **store path that changes on every rebuild**.
We made the path unstable. The assumption upstream is entitled to make is the
one our port breaks.

That is section 3 in its exact shape: name the variable that separates this
machine from every machine the code was written for. Here it is the one thing
the port changes about that variable -- its stability, not its meaning.

**And somebody has already hit this once.** `omarchy-restart-shell:8` reads the
session's value instead of the caller's:

```sh
session_omarchy_path=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
```

So the workaround exists, in one script, for the same mismatch -- which says
this is a class rather than an instance, and that whatever is done should be
findable by whoever meets the next one.

## Proposed outcome

- A plugin keybind works immediately after a rebuild, without a re-login or a
  shell restart.
- A machine where it cannot work says so, rather than failing silently. A
  keybind that does nothing is the worst available outcome and is what happens
  today.
- Whatever is chosen is recorded where the next person meeting this class will
  look, not only in the code.

## Affected users and systems

- Anyone who rebuilds while logged in -- which is the ordinary way to use this,
  and what `omarchy update` does.
- Every plugin keybind and menu row that reaches the shell over IPC.
- Not Arch, and not upstream: the path is stable there.

## Constraints

- **A patch carried here is re-applied at every source bump** (section 11), so
  if the answer is a patch it has to be small enough to survive that, and the
  bump procedure has to know about it.
- **The session's value is not always available.** `systemctl --user
  show-environment` answers for a logged-in session; a script run from a
  systemd system unit, or before login, has no session to ask -- the same
  boundary #950 dealt with.
- **Must not break the ordinary case**, where caller and shell agree. That is
  every call on a machine that has not rebuilt since login.

## Open questions

1. **Where does the fix live?** Three shapes, and they differ in how well they
   survive a source bump:
   - **Patch `omarchy-shell`** the way `omarchy-restart-shell` already reads the
     session value. Smallest, and re-applied at every bump.
   - **Put a stable path in front of `OMARCHY_PATH`** -- a symlink under `/etc`
     or `/run` that the module repoints, so upstream's match-on-path assumption
     becomes true here and nothing needs patching, now or ever. Bigger, and it
     removes the class rather than this instance.
   - **Match on something other than the path** (`qs ipc --any-display`, or an
     instance id), which the issue also suggests. Depends on what Quickshell
     offers and is the one I know least about.

   My inclination is the **stable path**, because it makes upstream's assumption
   true instead of teaching each script to work around its being false -- and
   because there are already two scripts working around it. But it is the
   largest of the three and I would rather put that trade to you than pick it
   quietly.

2. **Should this fail loudly when it cannot resolve?** Today it is silent. A
   keybind that says nothing is indistinguishable from a keybind that is not
   bound, which is how this reached a user rather than a log.

## Not in scope

- `omarchy-restart-shell`'s own five-second kill timeout (#953), which is a
  different failure in the same area and is upstream's.
- Anything about how plugins are enabled or which keybinds exist.
