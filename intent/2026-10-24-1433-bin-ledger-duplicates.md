---
status: draft
issue: 1433
author: olafkfreund
---

# Intent: the bin ledger holds one row per command, and its check says so

## Problem

`data/bin-ledger.nix` has two rows each for `omarchy-install-hermes-cli`
and `omarchy-install-openclaw-cli`.

- One pair is at lines 281 and 286, from #1335 (Omarchy v4.0.5).
- The other is at lines 751 and 756, from #1405 (v4.5.0-rc1).

So the file does not evaluate as Nix (`nix-instantiate --parse`: *attribute
'omarchy-install-hermes-cli.class' already defined*). Every other `data/*.nix`
file parses.

`checks.bin-ledger` stays green. `.github/scripts/check-bin-ledger.py:445-449`
reads the ledger with a regex into a dict, so the later row silently replaces
the earlier one.

**The rows that are ignored are the more accurate ones.** Checked against
upstream's scripts at `main`'s pin (`03ff1eff`):

- **hermes:** `systemctl --user stop omarchy-hermes-theme.service` runs
  only after a `--now` set-up, before it re-runs the theme setter.
  - #1335's row (ignored): "on --now only". Correct.
  - #1405's row (in force): "before reinstalling". Not what the script does.
- **openclaw:** the script stops, disables, queries and restarts the
  `openclaw-<role>` user units.
  - #1335's row (ignored): "stops, disables and queries". Close.
  - #1405's row (in force): "stops and checks … around an upgrade". This
    leaves out the disable.

Nothing fails today, because both rows carry the same `class` and `allow`.
But the ledger's rule is that every row is a claim the check holds true. A
shadowed row is a claim nobody checks, and an edit can land in the copy that
is ignored. The same thing can happen to any command at the next bump.

## Proposed outcome

- Each command has exactly one row. Its `reason` matches what the script
  does at the current pin.
- `data/bin-ledger.nix` evaluates as Nix.
- `checks.bin-ledger` fails, naming the command, when a second row for the
  same command appears.

## Affected users and systems

- `data/bin-ledger.nix` and `.github/scripts/check-bin-ledger.py`, plus
  `tests/bin-ledger.nix` if a fixture is needed for the red case.
- No user-facing change: the ledger is documentation that a check enforces.
- Edge carries the same duplicates, and gets the fix when `main` merges into
  it at the next edge run.

## Constraints

- **The check stays a regex over the text.** The comment at
  `check-bin-ledger.py:430-437` gives the reason: it reads the file the same
  way `check-menu-mapping.py` reads `data/apps.nix`. The duplicate guard
  belongs in that loader.
- **§1:** the new guard has to be seen failing on a real duplicate before it
  counts.
- **A CI-gate change needs the owner** (§11). A new failure condition in
  an existing check is not a workflow change. The PR will say so anyway.

## Open questions

1. **Which row survives?** I recommend one row each, with a reason
   rewritten from the script at the current pin (the wording above). Delete
   the duplicate at lines 751–760.
2. **Is the guard enough, or should every `data/*.nix` file also be
   parse-checked?** I recommend the guard only. It covers the loader that
   hid this. The other data files parse today, and adding a `--parse` sweep
   would be a new check with nothing it has caught yet. If you want the
   sweep as well, say so.
