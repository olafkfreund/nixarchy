---
status: draft
issue: 1209
intent: intent/2026-10-06-1209-detached-journal-race.md
---

# Spec: a detached rebuild's own output always reaches its log

## What is known about the cause

- It is intermittent. On p620, 2 of 3 local `checks.session` runs lost the
  line, and 1 passed. CI lost it on PR #1208.
- When it is lost, the line is still in the journal. The console shows it
  with its identifier and PID (`nixarchy-apply[27151]: nixarchy: refusing to
  rebuild ...`). It is missing only from
  `journalctl --user -u nixarchy-rebuild --invocation=<id>`.
- The diagnostic run meant to capture the lost line's fields passed, so the
  exact missing field is not captured. The likely mechanism is journald
  resolving per-process metadata (the unit's cgroup, and its invocation ID
  from the cgroup) after the process has already exited, which the unit's
  fast refusal makes likely.

The design below does not depend on which of those fields is lost.

## Design

### 1. The run's own lines carry a fixed identifier

`systemd-run` in `nixarchy-apply --detach` (`modules/apps.nix:3561`) gains
`-p SyslogIdentifier=nixarchy-rebuild`. The identifier is part of the stdout
stream's header, which systemd writes when it connects the unit's output to
journald. It does not depend on journald looking anything up in `/proc` or the
cgroup, so a line written just before exit still has it. Today the identifier
defaults to the executable name (`nixarchy-apply`), which the foreground
`nixarchy-apply` shares; a fixed, unit-specific name keeps the two apart.

### 2. `--log` scopes by time and identity, not invocation alone

`nixarchy-apply --log` (`modules/apps.nix:3510-3529`), for the **current**
run, i.e. no `--invocation` given, which is what the panel's copy-log uses
(`pkgs/rebuild-panel/RebuildState.qml:130`):

- reads the run's start time from the unit:
  `systemctl --user show -p InactiveExitTimestamp --timestamp=unix --value nixarchy-rebuild`
  (`@<epoch>`), the moment this invocation started;
- shows `journalctl --user --no-pager -o cat --since @<start>` matched on the
  unit's own lines **or** the identifier:
  `_SYSTEMD_USER_UNIT=nixarchy-rebuild.service + USER_UNIT=nixarchy-rebuild.service + SYSLOG_IDENTIFIER=nixarchy-rebuild`.

Only one `nixarchy-rebuild` can run at a time (a second `--detach` exits 3,
`tests/session.nix`), so everything from that start time onward under those
names belongs to this run or a later one. A later one would have moved the
start time. This keeps #986's "this run only" property.

With an explicit `--invocation <id>`, an older run, the existing
invocation filter stays: there is no start time to read for a past run, and
the panel never asks for one.

With no invocation at all (never detached), the existing `-n 200` cap stays.

`--follow` keeps working: `-f` is appended as today.

### 3. The test asserts on what the user sees

`detached_log` in `tests/session.nix` (`:805-818`) reads the log through
`nixarchy-apply --log` instead of its own `journalctl --invocation` command,
via the existing `invocation_journal` wait in `tests/session-journal.py`. The
assertion text stays the same: the refusal must be in the log a user copies.
The missing-flake section (`:781-783`) does the same.

`tests/session-journal-race.nix` (the #1133 unit test of the wait helper)
is unchanged. It stubs the command, and the command string is what changes.

## Alternatives rejected

- **A longer wait.** The line is not late; it is never attached to the
  invocation. #1133 already waits 30 s.
- **Drop `--invocation`, keep only `-u`.** If the lost field is the unit
  rather than only the invocation, `-u` misses the line too, and without a
  time bound it returns the unit's whole history (#986).
- **`systemd-cat`/`logger` inside `nixarchy-apply`.** That rewrites how every
  line is emitted. The identifier gives the same tag with one property.
- **`sleep` before the refusal exits.** A guessed number, and the intent rules
  it out.
- **Mark the assertion flaky.** The intent's default is to fix it. The bug is
  user-facing, not only a test problem.

## Risks

- **Clock steps between the run's start and the read** (NTP at boot). A
  backwards step could drop the run's first lines from `--since`. The unit
  starts well after boot, so this is unlikely. A forward step adds nothing
  wrong, because the identity match still applies.
- **`InactiveExitTimestamp` semantics** for a `RemainAfterExit=yes` unit that
  failed: it must be this invocation's start, not the previous one's. The plan
  verifies it in the VM (two runs back to back, each `--log` showing only its
  own lines).
- **Field names for user units** (`_SYSTEMD_USER_UNIT` vs `USER_UNIT`) differ
  between lines the process writes and lines the user manager writes. Both are
  matched; the plan confirms systemd's "Started/Failed" lines still appear.

## Verification

- `checks.session` passes 3 times in a row on p620, announced on the agent
  bus. The race showed in 2 of 3 runs before, so 3 clean runs is evidence, not
  proof.
- In the same runs, the two back-to-back detached runs (refusal, then
  `ALLOW_BRANCH_DEPLOY=1`) each show only their own lines through
  `nixarchy-apply --log`. The existing asserts already check both directions.
- `tests/session-journal-race.nix` still passes.
- `nix fmt -- --ci`, statix, deadnix: clean.
