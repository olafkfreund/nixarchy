---
status: approved
issue: 1033
intent: intent/2026-09-28-1033-takes-effect-at-next-login.md
---

# Spec: the wizard explains both halves, and offers the half it can fix

## The open questions, settled

1. **Offer to start it.** The wizard already runs `nixarchy secret enroll`
   and `nixarchy secret new` on the user's behalf, so starting a unit is not
   a new kind of action for it. Saying "run this yourself" when it could run
   it is the friction this issue is about.
2. **The `OMARCHY_PATH` check lives here, not in `doctor`.** `doctor`
   answers "what is wrong with this machine"; this answers "why did the thing
   I just enabled not appear". A stale `OMARCHY_PATH` is only interesting in
   the second question, and a person reading the remote-desktop wizard is
   already asking it.

## Design

### 1. "Enabled but not running" becomes an explanation and an offer

Today:

    ! enabled but not running -- systemctl --user status hypr-rdp

which sends the reader to a command that reports `inactive` and no cause.
Instead: say that the unit is pulled in by `graphical-session.target` at
login, so a unit added since the session started is never picked up; then
offer to start it.

The existing distinction stays. Over SSH, with no `WAYLAND_DISPLAY`, the unit
is *correctly* idle and must not be reported as a problem -- the current code
already gets this right and the new message must not undo it.

### 2. A stale `OMARCHY_PATH` is detected and named

    session reads : $OMARCHY_PATH
    system provides: $(readlink -f /run/current-system/sw/share/omarchy)

When those differ, the session predates a rebuild, and any menu row added by
that rebuild is absent -- which is exactly how "this menu does not exist at
all" was reported and then diagnosed by hand. The wizard says so, and says
what it cannot do: a new session is the only fix, because `OMARCHY_PATH` is
set when the session starts.

### 3. The manual covers the first enable

`docs/manual/remote-desktop.md` documents restarting after a **password**
change and says nothing about the first enable, which is the common case and
the one where the reader has no reason to suspect a unit exists.

## Alternatives rejected

**Starting the unit from an activation script.** It would fix half of this
and nothing of the menu, it runs for every user on every rebuild, and it
starts a service without being asked. The wizard asking is better behaviour
and covers the case the user is actually in.

**Moving the unit to Home Manager** for `startServices = "sd-switch"`. Real,
and larger: the unit needs `sops.templates`, which is NixOS-level, so the
two halves would straddle. Worth its own issue if the pattern recurs.

**Refreshing `OMARCHY_PATH` in the wizard.** Cannot be done: it is the
session's environment, and a child process cannot change it for the parent.
Claiming otherwise would be worse than silence.

**Putting both checks in `doctor`.** Question 2 above.

## Risks

- **Wording is the deliverable and no check can read English.** Same class as
  the documentation in #1015. Mitigated only by it being short and in the
  place the reader already is.
- **The `OMARCHY_PATH` comparison could be noisy.** If the two paths differ
  for a legitimate reason -- a user pointing `OMARCHY_PATH` somewhere
  deliberately -- the message would be wrong. It is phrased as an
  observation, not an error, and the check is skipped when the variable is
  unset.
- **Offering to start a unit that then fails** leaves the user with an error
  rather than a silence, which is an improvement, but the wizard should show
  what happened rather than swallow it.

## Verification

| what | how | break it by |
|---|---|---|
| the verbs still parse | `tests/menu-verbs.nix`, already registered | respelling the `case` block |
| the script is sound | `bash -n` and `shellcheck` | — |
| the stale-path branch fires | run it with `OMARCHY_PATH` pointed at a different tree | — it must say so, and say a new session is the fix |
| the SSH case is unchanged | run it with `WAYLAND_DISPLAY` unset | it must still report a correct idle, not a problem |
| the offer works | run it on a machine where the unit is enabled and stopped | the unit is running afterwards |

Every one of these is runnable on p620 right now, because p620 is a machine
with hypr-rdp enabled and a session that has already gone stale once.
