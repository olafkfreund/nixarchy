---
status: approved
issue: 1033
spec: spec/2026-09-28-1033-takes-effect-at-next-login.md
---

# Plan: the wizard explains both halves, and offers the half it can fix

**Written after the implementation, and that is a gate skipped.** The intent
and spec were approved, and then commit `2389f03` implemented them with no
`plan/` file. The managed workflow forbids implementation edits before the
plan is approved. This file records what was done against the approved spec,
names the one deviation, and lists the verification still owed. #1035 does
not merge until this plan is approved and the steps below marked *owed* are
done.

## Approved decisions, carried from the spec

- **Offer to start the unit.** `nixarchy remote serve` already runs
  `secret enroll` and `secret new` on the user's behalf, so starting a unit
  is not a new kind of action for it.
- **The `OMARCHY_PATH` check lives in the wizard, not `doctor`.** It answers
  "why did the thing I just enabled not appear".
- **"Enabled but not running"** becomes an explanation: the unit is pulled
  in by `graphical-session.target` at login, so a unit added since the
  session began is never picked up. The SSH case (no `WAYLAND_DISPLAY`)
  stays a correct idle, not a problem.
- **A stale `OMARCHY_PATH`** is compared against
  `readlink -f /run/current-system/sw/share/omarchy`. It is phrased as an
  observation, skipped when the variable is unset, and says a new session is
  the only fix, because a child process cannot change it.
- **The manual** covers the first enable, not only a password change.
- **Rejected:** starting from an activation script, moving the unit to Home
  Manager, refreshing `OMARCHY_PATH` from the wizard, and putting both checks
  in `doctor`. The reasons are in the spec.

## One deviation from the spec

**Secret detection reads the rendered config** (`has_rendered()`,
`/run/secrets/rendered/hypr-rdp.toml`) before guessing
`hosts/$HOST/secrets.yaml`. Running the new wizard on p620 reported "no
secret" and "no rule for this host" while the daemon was serving with that
secret, because p620 points `sopsFile` at `secrets/hosts/<host>/rdp.yaml`.
That is the same defect #1033 is about, telling somebody something untrue
about their own machine, so it was fixed in the same commit rather than
filed. Only the file's existence is checked; nothing is read out of it.

## Steps

1. `pkgs/omarchy/nix-bin/nixarchy-remote`, `report()`: the "enabled, and not
   running yet" explanation, `needs_start=true`, and the stale-`OMARCHY_PATH`
   observation. *Done in `2389f03`.*
2. `pkgs/omarchy/nix-bin/nixarchy-remote`, after `report`: the offer to
   start the unit. On failure it prints `systemctl --user status` advice and
   the last five journal lines rather than swallowing them. *Done in
   `2389f03`.*
3. `has_rendered()` and its use in `has_secret` and `report()` (the
   deviation above). *Done in `2389f03`.*
4. `docs/manual/remote-desktop.md`: the first-enable section. *Done in
   `2389f03`.*
5. **Verification.** Rows are marked by what the commit shows, not by
   assumption:

| what | how | state |
|---|---|---|
| the verbs still parse | `tests/menu-verbs.nix` | **done**: `omarchy` green on #1035 |
| the script is sound | `bash -n`, `shellcheck` on the shipped file | **owed** |
| the stale-path branch fires | `OMARCHY_PATH=<another tree> nixarchy remote serve --status` | **done on p620** (per `2389f03`); **owed**: a run with the variable unset, which must print nothing about it |
| the SSH case is unchanged | run over SSH (no `WAYLAND_DISPLAY`) | **owed**: must say "not running, because this is not a graphical session" |
| the offer works | on a session where the unit is enabled and stopped, answer yes | **owed**. Until #1038 is deployed on the host, the daemon dies on Hyprland 0.56, so this exercises the "did not stay up" branch and must show the journal lines. After the deploy, "running". |

## Tests

| command | expected |
|---|---|
| `bash -n pkgs/omarchy/nix-bin/nixarchy-remote` | exit 0 |
| `shellcheck pkgs/omarchy/nix-bin/nixarchy-remote` | no new findings against `main`'s copy |
| `env -u OMARCHY_PATH nixarchy remote serve --status` | no stale-session line |
| same with `OMARCHY_PATH=/nix/store/…-other/share/omarchy` | the session/system pair and "Log out and back in" |
| `ssh <host> nixarchy remote serve --status` | "not running, because this is not a graphical session" |
| `nixarchy remote serve`, unit stopped, answer yes | before the #1038 deploy: the "did not stay up" branch plus journal lines. After it: "running". |

## Rollback

Revert `2389f03`. The wizard goes back to the one-line "enabled but not
running", and no state on any machine changes.
