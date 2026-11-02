---
status: approved
issue: 1558
intent: intent/2026-11-02-1558-delegate-actions.md
---

# Spec: a notification with buttons keeps its buttons while the companion holds the lease

## Design

1. **Do not delegate a row that carries actions.** In
   `pkgs/omarchy/903-notification-delegate.patch`, extend the eligibility
   condition at `Service.qml`'s delegate branch (patched line 699) with:

   ```js
   && actionsOf(key, refsRevision).length === 0 && !row.execActions
   ```

   - **`actionsOf(key, revision)` is upstream's own helper.** It returns
     the named sender actions, without `default` or `settings`, the same
     list the card draws as buttons. `refs[key]` is set at line 674, before
     this branch, so it sees the actions of the notification being handled.
   - **`row.execActions` is Omarchy's exec-action field.** It is `""` when
     empty (`Store.js:45`, `actions ? JSON.stringify(actions) : ""`), so
     `!row.execActions` is false only when exec actions exist.
   - **A `default`-only notification still delegates.** The companion's
     `activateKey` fires `default`, so nothing is lost.
   - **An update that adds actions comes back to the shell.** It no longer
     qualifies, so the existing `undelegate(key)` after the branch pops it
     up as a card, which the comment there already describes.

   A one-line comment states the reason (#1558).
2. **Prove it in `checks.session`.** In `tests/session.nix`, beside the
   `delegated-133` cases (~line 1048), hold a lease and send `notify-send
   -a teams-for-linux -A more=More -- actions-1558 hi`. It runs in the
   background with every fd redirected, because `-A` waits for a reply and
   would hang the driver. Then assert:
   - it appears in `live.json`, so it is shown as a card;
   - it never appears in the `delegate` queue;
   - an ordinary `delegated-133`-style row sent in the same lease is still
     queued, so the guard did not switch delegation off.

## Alternatives rejected

- **Carry the actions to the companion and add `notifications.invokeAction(key,
  action)` IPC.** It needs a change in the companion's repo, which has
  issues disabled, and a protocol change on both sides. It stays possible
  later; this fix does not block it.
- **Read `notification.actions` directly.** That repeats the
  `default`/`settings` filtering `actionsOf` already does, and could
  disagree with the buttons the card draws.

## Risks

- **The patch is re-applied at every Omarchy bump.** The change adds two
  clauses to a line the patch already owns, so it adds no new context to
  rebase.
- **Apps that send named actions on every notification,** chat apps among
  them, now show cards during a lease instead of the snowflake. The issue
  asked for exactly that.

## Verification

- **§1:** with the two clauses removed, the new session assertion fails
  because `actions-1558` is in the delegate queue and not in `live.json`.
  With them, it passes.
- **The existing delegate cases** (`delegated-133`, `giveback-133`,
  `lapse-133`, `upd-133`, `crit-133`) still pass.
- **Static checks:** `checks.patched-files` and the `omarchy` package build
  are green. The patch applies.
