---
status: draft
issue: 896
author: olafkfreund
---

# Intent: the rebuild panel's buttons are driven by a check, not only by hand

Closes #896.

## Problem

`nixarchy.rebuild` shipped in #895 with three of its four promises checked by
hand only.

What covers it today:

| check | what it proves |
| --- | --- |
| `checks.qml` | its three QML files parse -- and only that |
| `checks.apply-staging` | the unit-state mapping, because that lives in `nixarchy-rebuild-state` rather than in QML |
| `checks.session` | `nixarchy-plugin nixarchy.rebuild` opens the panel over a running unit |

What nothing reaches: pressing **Rebuild now**, **Copy log** or **Open full log
in terminal**, and reattaching to a running rebuild after the panel is closed
and reopened.

That is written down -- `tests/AGENTS.md`, "The panel one: nothing in the suite
presses a button" -- and writing it down is the weaker half of AGENTS.md §3's
rule. A documented hole gets tested by a human; an undocumented one gets tested
by a user. This one is documented and otherwise untested, which means the first
person to find a broken button is whoever clicks it.

It matters more than a normal panel gap because of what the buttons do. **Rebuild
now** is the only path that starts an irreversible switch of the machine, and
the panel exists precisely so that path is not one stray click (#895's "it asks
before it switches"). A regression that made the button start nothing would look
like a dead panel; one that made it start on open would be a one-click switch.
Neither is visible to any check that runs today.

## Proposed outcome

On every pull request, `checks.session` drives the panel's three actions in a
real booted desktop and asserts what each one did:

- **Rebuild now** starts the `nixarchy-rebuild` unit, and nothing else does;
- **Copy log** puts the unit's journal on the clipboard;
- **Open full log in terminal** launches the terminal with the journal;
- closing and reopening the panel over a running unit still reports that unit.

And the panel opening on its own no longer starts a rebuild -- asserted
directly, rather than being true because nobody wrote the opposite.

## Affected users and systems

- `pkgs/rebuild-panel/Panel.qml` -- the IPC surface the shell exposes.
- `tests/session.nix` -- where the assertions go; it already logs in through
  the greeter and already drives this unit.
- `tests/AGENTS.md` -- the recorded hole shrinks to what genuinely remains.

No user-visible behaviour changes. Mode A is untouched: the panel is already a
`defaultPluginSet` entry that resolves to nothing without
`programs.nixarchy.enable`.

## Constraints

- **Must not become a second way to start a rebuild.** The IPC surface is for
  a check to press what a person presses. If an IPC call can start a switch
  that the button's own guards would refuse, the check is testing a path no
  user has. Whatever the button does and whatever IPC does must be one code
  path.
- **Must not be read by OCR.** #765 PR 1 established this theme is unreadable
  to the test's OCR, which is why the existing probe waits on a
  `polkit-agent-helper@*` unit rather than on text. Assertions here are system
  facts (a unit exists, a file's owner, a process started), never pixels.
- **No new `checks.<name>`**, so no workflow edit and no CI-gate change (§4,
  §11). The assertions extend a check a PR-triggered workflow already builds.
- **`checks.session` does not run locally** (`tests/AGENTS.md`), so every
  red/green pair for this work costs a CI round trip. That is a cost to plan
  for, not a reason to skip §1.
- The session VM is offline and cannot evaluate its own flake, so a *successful*
  rebuild still cannot be staged there (#805's recorded hole). "Rebuild now
  started the unit" is provable; "the rebuild succeeded" is not.

## Open questions

1. **Does `Copy log` belong in the check at all?** It shells out to `wl-copy`,
   so asserting it means asserting a clipboard round-trip inside the VM. That
   may be worth it, or may be the one button left to a person. I lean towards
   including it -- `wl-paste` in the same session is a system fact, not a
   pixel -- but it is the weakest of the three.
2. **Should the panel keep a separate "start" entry point at all**, or should
   the check press the button by driving the existing `toggle` and then a
   generic `invoke("rebuild")`? The first is simpler to assert; the second
   keeps the IPC surface from growing a verb per button. This is the decision
   the spec should settle.
3. **Is "one dialog per Apply" in scope?** I think not: it needs a real switch
   with a network, is already a named hole from PR 1, and folding it in here
   would make this issue unclosable. Confirming that keeps the scope honest.
