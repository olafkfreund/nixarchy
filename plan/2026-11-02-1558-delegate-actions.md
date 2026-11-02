---
status: approved
issue: 1558
spec: spec/2026-11-02-1558-delegate-actions.md
---

# Plan: a notification with buttons keeps its buttons while the companion holds the lease

## Approved decisions

- **Option 2:** a notification that carries a named sender action or an
  Omarchy exec action is not delegated. It stays a normal card with its
  buttons. Every other notification is still delegated.
- **The guard is two clauses on the existing eligibility condition** in
  patch 903: `actionsOf(key, refsRevision).length === 0 && !row.execActions`.
  - `actionsOf` is upstream's helper. It drops `default` and `settings`,
    and `refs[key]` is set before the branch (Service.qml line 674 vs 699).
  - `execActions` is `""` when empty (`Store.js:45`).
- **The test** goes in `checks.session`, beside the `delegated-133` cases.
- **Rejected:** carrying actions to the companion with a new
  `invokeAction` IPC, which needs a companion-repo change; reading
  `notification.actions` directly.

## Steps

1. **`pkgs/omarchy/903-notification-delegate.patch`, the hunk with
   `if (delegated() && !Delivery.bypassesQuiet(row)` (~patch line 108).**
   - Add the two clauses to the condition's last line, before ` {`, as
     added `+` lines.
   - Add a one-line comment above it: `// A row with buttons stays a card: the companion can only fire "default" (#1558).`
   - Fix the hunk header's added-line count (`@@ -614,7 +694,N @@`) to the
     new total. Otherwise the patch fails to apply.
   - Verify: `nix build .#omarchy` (package tier: only when no install or
     edge verify is in flight, §6). Then grep the built `Service.qml` for
     `actionsOf(key, refsRevision).length === 0`.
   - Traps: a hand-edited patch with a wrong count fails at `patchPhase`.
     Regenerating the hunk by `diff -u` from an edited copy of the
     unpatched-plus-903 file is safer than counting.
2. **`tests/session.nix`, after the `crit-133` case (~line 1113, before
   `delegate 0`).** Inside a held lease:
   - Background `notify-send -a teams-for-linux -A more=More -- actions-1558 hi`
     with `>/dev/null 2>&1 </dev/null &`, inside `as_user`.
   - Send a plain `plain-1558`.
   - Assert `actions-1558` reaches `live.json`
     (`wait_until_succeeds(live_mentions("actions-1558"), timeout=30)`).
   - Assert the `delegate` output has `plain-1558` and does not have
     `actions-1558`.
   - Then close `actions-1558` so the background `notify-send` exits: use
     the shell's existing close path, or let its timeout run out with
     `-t 2000`.
   - Verify: the session driver builds, which type-checks the script.
   - §1: with step 1's clauses reverted, the VM run fails on the
     `live.json` assertion. With them, it passes. The VM run happens only
     when CI is idle (§6), otherwise in the PR's `system-session` job. The
     red half then comes from a probe run reusing CI's driver, as done for
     the screensaver fix.
   - Traps: `-A` blocks until a reply, so it must be backgrounded with
     every fd redirected, or `machine.succeed` hangs. No `${` in the
     Python (§5).

## Tests

- The `omarchy` package builds, and the patch applies.
- The session driver builds. `checks.session` passes in CI, with the §1
  red half captured.
- The existing `*-133` delegate cases still pass, in the same run.

## Rollback

Revert the PR. Delegation goes back to taking every eligible row.
