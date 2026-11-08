---
status: approved
issue: 1659
spec: spec/2026-11-08-1659-power-authorise-first.md
coders:
  1: codex  # a --fuzz=0 patch to exit_session where order is the whole fix
  2: codex  # the session-test block: polkit rules, a pending agent dialog, a cancelled schedule
reviewers:
  - codex  # tricky ordering logic and a VM probe that must fail without the patch
  - agy    # an independent read of the same diff
---

# Plan: reboot and power-off ask for authorisation before closing windows

## Decisions carried from the approved spec

1. `exit_session` in upstream's `bin/omarchy-system`, for reboot and
   shutdown, first runs `systemctl <reboot|poweroff> --no-wall --when=+5s`.
   logind checks authorisation when the shutdown is scheduled, so there is
   one prompt. On failure it sends the existing failure notification,
   returns non-zero, closes nothing, and keeps the marker. Only on success
   does it show the OSD, clear `re*-required`, and run
   `timeout 2s omarchy-hyprland-window-close-all --wait`. Logout is
   unchanged.
2. The `systemd-run ... --property=RuntimeMaxSec=30s` wrapper (line 75)
   gains `--property=ExecStopPost=`, which sends the critical failure
   notification when `$SERVICE_RESULT` is `timeout`.
3. A carried patch here, `pkgs/omarchy/1659-system-authorise-first.patch`,
   applied with `--fuzz=0` beside the others, with a `pkgs/AGENTS.md`
   section marked CARRIED. The owner files upstream (omacom/omarchy); no
   agent does.
4. Probes in `checks.session`: denied, timed out (agent registered and the
   dialog left unanswered), and allowed (schedule asserted, then cancelled),
   for both reboot and power-off, including the `--inhibited` path.

## Steps

1. **The patch** — copy the shipped script, edit, and diff:
   `cp $(nix build .#omarchy --no-link --print-out-paths)/share/omarchy/bin/omarchy-system a`,
   edit a copy `b`, and `diff -u` to make a `-p1` patch rooted at
   `share/omarchy` (`bin/omarchy-system`). Apply it in
   `pkgs/omarchy/default.nix` with a `patch -d "$out/share/omarchy" -p1
   --forward --fuzz=0 < ${./1659-system-authorise-first.patch}` line,
   placed with the other `bin/` patches (for example next to line 1129's
   `1625-no-mise.patch`).
   - In `exit_session` (lines 45-55), for `$action != logout`, the schedule
     comes first. Its failure path calls `omarchy-notification-send -u
     critical "$failed_title" "$failed_body"` and `return 1`.
   - At line 75, add `--property=ExecStopPost=<a small inline sh -c that
     tests [ "$SERVICE_RESULT" = timeout ] and notifies>`. The titles are
     `--setenv`'d into the unit so the stop command can read them.
   - In `pkgs/AGENTS.md`, after the notification-history section (line
     ~1380), add a 6-line "CARRIED" section: what, why
     (nixos_config#2761), and how it is dropped.

   Verify: `nix build .#omarchy` (package tier, gate first) applies the
   patch. `checks.patched-files` passes.
   Traps: §5, the `''` string makes `\$` literal and only `${` interpolates;
   `$SERVICE_RESULT` inside the unit property must reach systemd
   unexpanded, so check the built script, not the source. `--fuzz=0`
   means a context mismatch fails the build, which is wanted.
   `checks.install-phase-budget` measures `installPhase`, so keep the
   comment in AGENTS.md, not in `default.nix` (#1663).

2. **The probes** — `tests/session.nix`, a new block after the input-method
   block (line 3226 onward), each case as the session user:
   - **denied:** `/etc/polkit-1/rules.d/00-test-deny.rules` returns
     `polkit.Result.NO` for `org.freedesktop.login1.reboot*` and
     `power-off*`. Open a `foot` window. Touch the marker. Run
     `omarchy-system reboot --execute`. Assert: the window is still in
     `hyprctl clients -j`, the marker exists, a critical notification was
     sent (the notification store or `makoctl`-equivalent the session test
     already reads), and `ScheduledShutdown` is empty (`busctl
     get-property org.freedesktop.login1 /org/freedesktop/login1
     org.freedesktop.login1.Manager ScheduledShutdown`). Repeat with
     `shutdown --execute`, which goes through `systemd-inhibit ...
     --inhibited`.
   - **timed out:** the rule returns `polkit.Result.AUTH_ADMIN`. The
     session's polkit agent is running and its dialog is left unanswered.
     Run the menu form (`omarchy-system reboot`, no `--execute`) with
     `RuntimeMaxSec` shortened to 5 s through a test-only environment
     override the patch reads (`OMARCHY_SYSTEM_TIMEOUT`, default `30s`).
     Assert the transient unit's `Result=timeout`, the notification, the
     window, and the marker.
   - **allowed:** no rule. Run both verbs, and assert `ScheduledShutdown`
     is set. Then `systemctl <verb> --when=cancel` and assert it is empty
     again, so the VM stays up.
   - Remove the rule files after each case.

   Verify: the VM tier, when no runner is busy:
   `nix eval --raw .#checks.x86_64-linux.session.drvPath`, then
   `nix build '<drv>^*'`. §1: build once with the patch line removed from
   `default.nix`. The denied case must fail on "the window still exists".
   Capture it.
   Traps: confirm which polkit agent the session runs before writing the
   timeout case, and that it is up when the case starts. With no agent,
   polkit fails at once and the timeout never happens. Never `pkill` by
   name (§6). A shutdown scheduled and never cancelled would end the VM
   mid-test, so cancel inside a `try`/`finally`.

3. **Run, commit, PR** (session): `nix fmt -- --ci`, statix, deadnix,
   `checks.grep-q-pipefail`, `checks.patched-files`, `checks.omarchy`
   (package tier), `checks.session` (VM tier). One commit per step. PR body
   says `Closes #1659`, notes the patch is CARRIED, and asks the owner to
   file upstream. "@codex review"; merge with `--auto --merge
   --delete-branch`.

## Tests

| check | tier | expect |
|---|---|---|
| `omarchy`, `patched-files` | package / cheap | the patch applies with `--fuzz=0` |
| `session` | VM | denied, timed-out and allowed cases pass; fails with the patch reverted |
| fmt, statix, deadnix, `grep-q-pipefail` | cheap | pass |

## Rollback

Revert the PR. The patch line and file go, and `omarchy-system` is
upstream's again. Nothing persists on a machine: the scheduled shutdown is
the only state, and it fires or is cancelled within seconds.

## Deviations (Codex plan review, 2026-11-08, before coding)

1. **One failure notification.** `exit_session` returns non-zero without
   notifying. The existing `--execute` handler (lines 58-71) already
   notifies on a non-zero status.
2. **The timeout override is in step 1's patch:**
   `--property=RuntimeMaxSec=${OMARCHY_SYSTEM_TIMEOUT:-30s}`. It is
   undocumented and used only by the test. The `ExecStopPost` notification
   is added for the two power verbs only, not logout.
3. **The allowed and timeout cases launch from the desktop session**
   (`hyprctl dispatch exec`), so polkit sees the login session as the
   subject, as `tests/session.nix:652` explains. The denied case may use
   `su`, since a `NO` rule refuses any subject.
4. **The timeout result is read from the journal**, not from the unit,
   which `--collect` unloads. That means `journalctl --user` for the
   transient `run-*.service` with "Failed with result 'timeout'", plus the
   notification and the surviving window.
5. **Step 1's check proves the patch applies, nothing more.** The behaviour
   proof is step 2's revert-and-fail.
6. **Patch location:** `pkgs/omarchy/1659-system-authorise-first.patch`,
   beside the existing patches (all live in `pkgs/omarchy/`; there is no
   `patches/` directory). The spec's path named a directory that does not
   exist, so this follows the tree.
7. The new session block goes after the input-method block's final cleanup,
   not at line 3226.
