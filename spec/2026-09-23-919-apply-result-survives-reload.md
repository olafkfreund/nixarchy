---
status: approved
issue: 919
intent: intent/2026-09-23-919-apply-result-survives-reload.md
---

# Spec: an apply started from a panel tells you how it ended

## What the investigation found, before any design

The intent described this as "the switch reloads Hyprland and closes the
panel". Reading the tree changes that description in three ways, and each one
makes the fix smaller.

**1. A failed apply is already reported. A successful one is not.**

`pkgs/rebuild-panel/Panel.qml:58` is the whole of it:

```qml
visible: RebuildState.active || root.opened || RebuildState.state === "failed"
```

Running shows. **Failed shows.** Succeeded **hides**. So the bar widget already
survives whatever closed the panel and already reports the bad case — and the
case the user is actually waiting for, "it worked", is the one with no
indicator at all.

The intent said "an apply that fails is at least as visible as one that
succeeds" as an outcome to achieve. It is already true, in the wrong direction:
failure is visible and success is not.

**2. The result already persists, with no new mechanism.**

`modules/apps.nix:3620-3629` maps the `nixarchy-rebuild` unit's `SubState`,
`Result` and `ExecMainStatus` to idle/running/succeeded/failed, and `exited` +
`Result=success` + `code=0` is `succeeded`. #765 deliberately omits `--collect`
(*"it unloads a failed unit at once, which then reads Result=success"*), so the
unit stays loaded and that state outlives the panel, the shell reload, and the
session. Nothing durable needs inventing — intent question 1 is answered by
what is already there.

**3. What closes the panels is probably ours, and it is not Hyprland.**

The shell is **not** a systemd user unit in this tree, so a switch does not
restart it that way — it is started from Hyprland's `autostart.lua`. What does
close panels is documented in `modules/home.nix:1020` and `:1026`:

> the shell reloads every plugin on any event in `dir`

`dir` is `~/.config/omarchy/plugins/`. Activation writes a link only when its
target differs (#710), so:

- a rebuild that changes **any plugin's store path** writes a link → an event →
  the shell reloads every plugin → **every panel closes**;
- a rebuild that changes no plugin writes nothing → no event → panels survive.

That predicts exactly the behaviour the issue reports as the exception:
*"an apply whose configuration is unchanged does not reload, and the panel
stays open."* It also predicts something the issue does **not** claim, which is
how this gets tested: **an apply that changes packages but no plugin should
also leave the panel open.** If it does not, this diagnosis is wrong.

The `xkbcomp` and uwsm lines in the issue's journal are a separate, cosmetic
event — a keymap recompile and a blanked frame. They are what the reporter saw;
they are not what removed the panel.

## Design

**The bar widget holds the settled result until the user acknowledges it**
(owner's decision, 2026-09-23). Three changes, all in `pkgs/rebuild-panel/`.

1. **`Panel.qml`: the widget stays visible on `succeeded`.** The rule becomes
   visible while running, while open, while failed, **and while a settled
   result has not been acknowledged**. Failure keeps behaving exactly as it
   does today.

2. **An acknowledgement, so it does not stay forever.** Opening the panel is
   the acknowledgement: a settled result the user has looked at stops drawing
   in the bar. This needs no new UI and no new verb — the widget already
   toggles `root.opened`.

3. **`RebuildView.qml` says which run it is describing.** A settled state with
   no timestamp is ambiguous after a reboot, when the unit is still loaded from
   hours ago. The view gains the unit's `ExecMainExitTimestamp`, so "applied"
   carries when.

Nothing else changes. The other panels are untouched: they already hand off to
`nixarchy-apply` and exit, which is why intent's "must not require every panel
to be changed" is satisfied by construction rather than by discipline.

**The reload is investigated and deliberately not changed** (owner's decision:
in scope to investigate). The finding above goes in
`modules/AGENTS.md` beside the #710 note it extends, and the testable
prediction is written into the plan as a step. Suppressing the reload would
mean not reconciling plugin links during activation, which is the bug #710
fixed in the other direction; and a rebuild that genuinely changes plugin code
*should* reload it. There is nothing here worth changing — but there was
something worth knowing, and the issue's framing was wrong about it.

## Alternatives rejected

- **A notification on success and failure.** Survives any reload and needs no
  bar. Rejected because the widget already exists, already survives the reload,
  and already handles failure — a notification would be a second reporting
  path to keep in step with the first, for the half that is already built. It
  also cannot carry the log, which is what a failed apply needs.
- **The rebuild panel reopens itself after the reload.** Closest to what the
  user was looking at. Rejected as the most new machinery for the least
  additional truth: nothing in this tree summons a panel on its own, a panel
  that opens itself on every apply is intrusive on the successful path, and
  `summonBarWidget` resolves against instantiated widgets — so it would depend
  on the very reload that just tore everything down.
- **A durable record of the last apply** (a state file under
  `~/.local/state/nixarchy/`). Rejected: the unit already is that record, and a
  second copy is a second thing that can disagree with systemd.
- **Making failure louder than success** (intent question 4). Rejected as
  backwards — failure is already the visible one. The gap is the confirmation
  the user is waiting for, and the fix is symmetry, not more alarm.
- **Suppressing the session reload.** Rejected above: it is #710's fix run
  backwards, and a changed plugin ought to reload.

## Risks

- **The widget becomes permanently visible** if acknowledgement is wrong —
  a bar item nobody can dismiss is worse than one that hides too eagerly. The
  verification below asserts both edges: it appears on success, and it goes
  away once opened.
- **A stale `succeeded` after a reboot.** The unit is loaded from the last
  boot's apply, so without the timestamp the bar would claim a fresh success
  on every login. This is why change 3 is in the design rather than a nicety.
- **QML has no check in this suite.** `checks.qml` lints the patched shell;
  nothing drives a widget. So the logic that can be tested must live outside
  QML, as #765 PR 5 established by putting the state mapping in
  `nixarchy-rebuild-state` rather than in the panel. This spec adds no new QML
  logic beyond a visibility expression for that reason.
- **Real hardware only.** No VM here has a session that reloads its shell
  mid-apply. The on-screen half is unprovable in CI and will be named as such.

## Verification

| | how |
|---|---|
| the state mapping already returns `succeeded` | `checks.apply-staging` drives `nixarchy-rebuild-state` against a stubbed `systemctl`; extend it with the exited/success/0 case if it is not already covered |
| the widget's rule mentions `succeeded` | a grep-shaped assertion in the omarchy build, beside the existing `--replace-fail` anchors, so a rewrite upstream fails the build rather than silently dropping it |
| **the diagnosis in "3" above** | on a real session: apply a change that touches **packages but no plugin**, and confirm the panel stays open. If it closes, the plugin-watcher explanation is wrong and the plan says so |
| the on-screen behaviour | owner, once, on razer or p620: apply from a panel, watch the bar after the reload |

The third row is the one that matters, because it is the only one that can
falsify the reasoning this spec is built on. It is a prediction, not a
confirmation: the issue never claims it, and it follows only if the mechanism
is what `modules/home.nix` says it is.
