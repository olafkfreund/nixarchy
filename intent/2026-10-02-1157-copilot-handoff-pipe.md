---
status: approved
issue: 1157
author: olafkfreund
---

# Intent: the Copilot handoff survives a large failure log

## Problem

`.github/scripts/copilot-handoff.sh` hands a broken dependency bump to Copilot.
It dies exactly when the bump is broken worst.

Lines 41-45 build the error excerpt as a pipeline ending in `head -100`,
inside `$(…)`, under `set -euo pipefail`. When more than 100 lines match:

1. `head` exits;
2. the `grep` and `sed` feeding it are killed writing to a closed pipe
   (SIGPIPE);
3. `pipefail` turns that into a failed substitution;
4. `set -e` ends the script.

Run 36981682776 (2026-10-02) logged exactly that, after #1154's build broke
with a large Hyprland trace:

```
grep: write error: Broken pipe
sed: couldn't write 148 items to stdout: Broken pipe
Error: Process completed with exit code 2.
```

So #1154 was never handed off, and nothing else noticed: the handoff's failure
is one red run in a workflow nobody watches.

Nothing tests this script. `tests/AGENTS.md` already records this SIGPIPE
shape four times (around lines 1190-1411), so the lesson exists; the check does
not. `.github/scripts/readme-counts.sh:106` and `:156` use the same
`$(… | head -1)` and are safe only while their input stays small.

## Proposed outcome

- **The handoff completes on any size of log.** It posts the first 100
  matching lines, as intended, whether 5 lines matched or 5,000.
- **A check feeds the script a large failure log** through a stubbed `gh` and
  fails if the script dies. It is shown red on today's script.
- **`readme-counts.sh`'s two sites** either cannot SIGPIPE, or are shown safe
  with a reason.

## Affected users and systems

- `.github/scripts/copilot-handoff.sh`, and possibly
  `.github/scripts/readme-counts.sh`.
- A new cheap check under `tests/` and its `checks.*` entry. CI runs it with
  no workflow edit (§4).
- No machine is affected; this is CI tooling.

## Constraints

- **The workflow itself is not changed:** triggers, permissions and gates are
  a human's (§11). This changes only the script and adds a check.
- **The check must not call GitHub.** Stub `gh`, as the repo's other script
  checks do.
- **Prove the check fails on today's script** (§1).

## Open questions

None.
