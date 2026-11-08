---
status: draft
issue: 1659
intent: intent/2026-11-08-1659-power-authorise-first.md
---

# Spec: reboot and power-off ask for authorisation before closing windows

## Design

### The mechanism: schedule the shutdown first (intent decision 3)

`systemctl reboot|poweroff --when=+<N>s` asks logind to *schedule* the
shutdown. logind checks authorisation when the request is made, not when
the timer fires. So the password dialog, if any, appears before anything
else happens, and the shutdown that follows needs no second prompt.
systemd 262 is what nixpkgs ships here, and `--when=` exists since 254.
`systemctl reboot --when=cancel` withdraws the schedule.

The patched `exit_session` in `omarchy-system`, for reboot and shutdown
(logout is unchanged):

1. `systemctl <verb> --no-wall --when=+<N>s`. On failure (refused,
   cancelled, polkit error): send the existing failure notification and
   return non-zero. Windows are untouched and the marker is not cleared.
2. Only then show the OSD, clear the `re*-required` marker, and run
   `timeout 2s omarchy-hyprland-window-close-all --wait`, as today.
3. Done. logind fires the shutdown at `+N`.

`N` is 5. The window-close step is bounded at 2 s, and its wait must finish
before logind tears the session down. Scheduled shutdowns within 5 minutes
create `/run/nologin`, which is right for a machine about to go down.

The unattended `--when` also covers the existing `--inhibited` path for
shutdown (`systemd-inhibit ... "$0" "$action" --inhibited`), because
`exit_session` is the one place both paths reach.

### The timeout (decision 2)

The `systemd-run --user ... --property=RuntimeMaxSec=30s` wrapper (line 75)
stays. Its limit now bounds the authorisation step, which is the one step
that can wait on a human. A dialog left unanswered past it kills the unit
before anything was scheduled or closed: the bad outcome (windows gone,
machine up) is no longer reachable. To report it, the wrapper gets
`--property=ExecStopPost=` running `omarchy-notification-send -u critical
"$failed_title" "$failed_body"` when `$SERVICE_RESULT` is `timeout`. That is
the stock way a unit learns how it ended, and it needs no watcher process.

### The patch (decision 1)

`pkgs/omarchy/patches/9xx-system-authorise-first.patch`, at the next free
number, applied with `--fuzz=0` beside the others, with a `pkgs/AGENTS.md`
section marked CARRIED until omacom/omarchy takes it. The section names the
upstream issue the owner files. No agent files it.

## Alternatives rejected

- **`pkcheck --allow-user-interaction` first, then `systemctl`.** polkit
  re-asks for the second call unless the matching rule returns an
  `auth_*_keep` result, and the owner's rule (nixos_config#2761) is the very
  case that asks. The result would be two prompts, or one plus the same bug.
- **Reboot first, close windows in the shutdown path.** logind starts the
  shutdown as soon as it is authorised, so apps would get no graceful close.
  Upstream closes them first for that reason.
- **A nixarchy polkit rule allowing login1 reboot without a password.** That
  overrides a hardening the owner chose deliberately.

## Risks

- **`/run/nologin` for N seconds.** Harmless at shutdown. A cancelled
  schedule removes it (systemd does so on cancel).
- **A lingering schedule.** If the window-close step fails or hangs, the
  shutdown still fires at `+N`, and an app that did not close loses unsaved
  work. Today is the same: the 2 s close is bounded and `systemctl` runs
  straight after it. The change keeps that bound and adds 3 s to it, and it
  does not add a new way to lose work.
- **Upstream drift:** a source bump that rewords `exit_session` fails the
  patch at build time (`--fuzz=0`), not silently.

## Verification

- `checks.session` (VM tier), new block. It installs a polkit rule that
  returns `polkit.Result.NO` for `org.freedesktop.login1.reboot*`, opens a
  window, runs `omarchy-system reboot --execute` as the session user, and
  asserts: the window still exists (`hyprctl clients`), the marker file is
  still present, a critical notification was sent, and logind's `ScheduledShutdown` property is empty (`busctl
  get-property org.freedesktop.login1 /org/freedesktop/login1
  org.freedesktop.login1.Manager ScheduledShutdown`). §1 break: the patch
  reverted fails "the window still exists".
- **The timeout path:** the same block with a rule returning
  `AUTH_ADMIN`, while the session's polkit agent **is registered** (the
  session runs one) and the test never answers its dialog. With no agent,
  polkit would fail at once and never reach the limit. `RuntimeMaxSec` is
  overridden to 5 s by the test. It asserts that the unit's result was
  `timeout` (`systemctl --user show -p Result` on the transient unit), that
  the timeout notification was sent, and that the window survived.
- **Power-off and the inhibited path:** the denied case is repeated for
  `omarchy-system shutdown --execute`, which goes through
  `systemd-inhibit ... --inhibited`, so a mistake confined to power-off or
  that wrapper fails too.
- **The allowed path**, for both verbs: no rule. Assert a
  shutdown was scheduled
  (`ScheduledShutdown` set), then cancel it with `--when=cancel` so the VM
  stays up. This proves the patch still reboots on a stock machine.
- `checks.omarchy` (package tier) for the patch applying, plus
  `checks.patched-files`, statix, deadnix, `nix fmt -- --ci`.
