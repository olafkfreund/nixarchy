---
status: draft
issue: 1209
spec: spec/2026-10-06-1209-detached-journal-race.md
---

# Plan: a detached rebuild's own output always reaches its log

## Approved decisions (from the spec)

- The detached unit's own lines get a fixed tag:
  `systemd-run ... -p SyslogIdentifier=nixarchy-rebuild`. The identifier
  travels in the stdout stream header, so a line written just before exit
  keeps it whatever journald fails to look up afterwards.
- `nixarchy-apply --log` with no `--invocation` (the current run, which the
  panel copies) reads the run's start time
  (`systemctl --user show -p InactiveExitTimestamp --timestamp=unix --value nixarchy-rebuild`)
  and shows `journalctl --user --no-pager -o cat --since @<start>` matched on
  `_SYSTEMD_USER_UNIT=nixarchy-rebuild.service + USER_UNIT=nixarchy-rebuild.service + SYSLOG_IDENTIFIER=nixarchy-rebuild`.
  With an explicit `--invocation <id>`, today's filter stays. With no run at
  all, today's `-n 200` stays. `--follow` appends `-f` as now.
- `tests/session.nix` reads the detached logs through `nixarchy-apply --log`
  (what the user sees), keeping the same assertion texts.

## Steps

1. **`modules/apps.nix:3561` (`systemd-run` in `--detach`).** Add
   `-p SyslogIdentifier=nixarchy-rebuild` beside the existing `-p` flags,
   with a one-line reason (#1209).
   → verify by step 3's VM run: `journalctl --user -t nixarchy-rebuild`
   shows the refusal.
   Traps: the string is inside a Nix `''` string, so a literal `${` needs
   `''${`. Keep the `-p` list's alignment.

2. **`modules/apps.nix:3510-3529` (`--log`).** When `$invocation` was **not**
   given on the command line (it is filled from `rebuild_state` instead), read
   `start=$(systemctl --user show -p InactiveExitTimestamp --timestamp=unix --value nixarchy-rebuild)`
   (value `@<epoch>`, or empty) and, if it is non-empty, run
   `journalctl --user --no-pager -o cat --since "$start" _SYSTEMD_USER_UNIT=nixarchy-rebuild.service + USER_UNIT=nixarchy-rebuild.service + SYSLOG_IDENTIFIER=nixarchy-rebuild`
   plus `-f` when following. An explicitly given `--invocation` keeps the
   current `--invocation=` path. Empty start time and no invocation keeps
   `-n 200`. Distinguish "given" from "filled" with a separate variable set
   in the argument parser at `:3403`.
   → verify by step 3.
   Traps: `--timestamp=unix` needs systemd ≥ 251, which both 26.05 and
   unstable have. Check the value starts with `@` before using it.
   `journalctl` field matches with `+` are OR groups; do not mix them with
   `-u`. Comments: why, not what.

3. **`tests/session.nix:781-789` and `:805-818`.** Replace both
   `"journalctl --user -u nixarchy-rebuild --invocation=" + inv + " --no-pager -o cat"`
   commands with `"nixarchy-apply --log"`, run through `as_user(...)` as
   now. Keep `invocation_journal`'s `invocation` argument for its messages.
   Keep the assertion texts. Leave `tests/session-journal-race.nix` as is:
   it stubs whatever command it is handed.
   → verify by `nix build .#checks.x86_64-linux.session -L` passing
   **3 times in a row** on p620, each announced on the agent bus. In the log,
   both `detached_log` cases print their success lines (refusal present, and
   `ALLOW_BRANCH_DEPLOY=1` without the refusal), which also proves the two
   back-to-back runs do not see each other's lines.
   Traps: `nixarchy-apply --log` must run as the session user with
   `XDG_RUNTIME_DIR` and the user bus, which `as_user` already provides. A
   test that reads the wrong run passes the first case and fails the second,
   so both must be checked.

## Tests

- 3 consecutive green `checks.session` runs on p620.
- `nix build .#checks.x86_64-linux.session-journal-race` passes.
- `nix fmt -- --ci`, statix, deadnix: clean.

## Rollback

Revert the PR. `--log` returns to the invocation filter, and the race returns
with it.
