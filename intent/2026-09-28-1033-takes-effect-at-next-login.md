---
status: approved
issue: 1033
author: olafkfreund
---

# Intent: say that enabling remote desktop takes effect at next login

## Problem

Enable `programs.nixarchy.services.hypr-rdp`, rebuild, and **nothing
happens**. The service is not running and the menu row is not there. Neither
explains itself, so the reasonable conclusion is that the feature is broken
-- which is the conclusion the maintainer reached, about a module whose
manual page had been written that morning.

Two symptoms, one cause: **the session predates the change.**

| what you did | what you get | why |
|---|---|---|
| enable it, rebuild | service not running | `WantedBy=graphical-session.target` is evaluated when the target **starts**, at login. A unit written afterwards is enabled, correct, and never pulled in. NixOS does not start `systemd.user.services` on a switch either. |
| same rebuild | menu row absent | `OMARCHY_PATH` is fixed when the session starts. The row exists in the tree the *system* provides and not in the tree the *session* reads. |

`Restart=on-failure` cannot help: the unit has not failed, it has not run.

Both were hit for real on p620, twice, and the menu one was reported as
"this menu does not exist at all". It does -- in the new tree.

## Proposed outcome

A person who enables remote desktop and rebuilds is **told** what is
happening, in the place they are already looking:

- `nixarchy remote serve` says the unit takes effect at next login, and
  offers to start it now
- it notices when the session is reading a stale `OMARCHY_PATH`, and says
  the menu rows will not appear until the next login
- the manual says the same, for the first enable and not only for a password
  change

## Affected users and systems

- anyone enabling remote desktop for the first time, which is everyone once
- `pkgs/omarchy/nix-bin/nixarchy-remote` -- the `serve` report
- `docs/manual/remote-desktop.md`
- nothing at runtime: no option, no unit, no behaviour changes

## Constraints

**No new option.** This is a wording and diagnosis problem, not a
configuration one.

**Do not claim to fix what cannot be fixed here.** A new menu row genuinely
needs a new session; `OMARCHY_PATH` is set at session start. Offering to
start the unit is real; offering to refresh the menu would be a lie.

**The wizard must not print anything from the rendered config.** Unchanged,
and the reason is unchanged.

**Detection must be honest about "not running".** Over SSH the unit is
correctly idle, and the current code already distinguishes that. A new
message must not turn a correct idle state into an alarm.

## Open questions

1. **Should it offer to start, or just say how?** Offering is one prompt and
   removes the step; it also means the wizard starts a service, which it does
   not do today. I lean towards offering, since it already runs `enroll` and
   `new` on the user's behalf.
2. **How does it detect a stale `OMARCHY_PATH`?** Comparing `$OMARCHY_PATH`
   with the current system's tree is how the problem was diagnosed by hand,
   and it is two lines. Whether that belongs in this wizard or in
   `nixarchy doctor` is a fair question -- doctor is where "what is wrong
   with this machine" lives.
