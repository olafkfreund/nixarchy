---
status: approved
issue: 1558
author: olafkfreund
---

# Intent: a notification with buttons keeps its buttons while the companion holds the lease

## Problem

While Nixi's snowflake companion holds the notification lease
(`notifications.delegate(ms)`, `pkgs/omarchy/903-notification-delegate.patch`),
the shell hands it every eligible notification instead of showing a card.
The row it hands over carries only key, app, source, summary, body, urgency
and category. The notification's named sender actions and Omarchy's exec
actions are dropped. A click on the companion goes through `activateKey`,
which can fire only the `default` action.

So a sender offering a named action, for example
`notify-send -A more="Tell me more" --wait`, never gets it invoked while
the snowflake is up. The user also sees the notification for less than a
second (`closed_reason: "delegated"` about 0.7 s after arrival).

Found with agent-say on p620 on 2026-11-02 (olafkfreund/nixos_config#2596).
The workaround there was to name the action `default`.

## Proposed outcome

- A notification that carries a named sender action or an exec action is
  not delegated. The shell shows it as its usual card, with working
  buttons, while the lease is held.
- A notification without such actions is still delegated, as today.
- `checks.session` proves both, while a lease is held.

## Affected users and systems

- Anyone running the nixi companion (p620 and razer today) with apps that
  send action buttons: agent-say, chat apps, calendar reminders.
- Only `pkgs/omarchy/903-notification-delegate.patch` and
  `tests/session.nix`. The companion's repo is unchanged.

## Constraints

- Stay inside this repo. The issue's other option, carrying actions to the
  companion and adding an `invokeAction` IPC, needs a companion change in a
  repo with issues disabled. It stays possible later.
- The patch must still apply to the vendored Omarchy tree. It is
  re-applied at every source bump, so the change is kept to the existing
  eligibility condition.
- The test's `notify-send -A` blocks until it gets a reply. It must run in
  the background with every fd redirected, or the driver hangs
  (`tests/session.nix`, the existing backgrounded calls).
- The check is shown failing without the patch change (§1).

## Open questions

None. The issue offered two options. This takes option 2, the one that
needs no companion change.
