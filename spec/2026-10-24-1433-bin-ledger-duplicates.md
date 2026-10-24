---
status: approved
issue: 1433
intent: intent/2026-10-24-1433-bin-ledger-duplicates.md
---

# Spec: the bin ledger holds one row per command, and its check says so

## Design

Two edits, and nothing else.

1. **`data/bin-ledger.nix`: one row each.**
   - Delete the second pair, the `omarchy-install-hermes-cli` and
     `omarchy-install-openclaw-cli` rows from #1405 at lines 751–760.
   - Rewrite the first pair's `reason` (lines 281–290) from the scripts at
     `main`'s pin (`03ff1eff`). `class = "vendor"` and
     `allow = "systemctl-user"` stay as they are:
     - **hermes:** "Vendored unchanged. Stops omarchy-hermes-theme.service
       only after a --now set-up, before re-running the theme setter;
       stopping a user unit is session state and carries no configuration."
     - **openclaw:** "Vendored unchanged. Stops, disables, queries and
       restarts the openclaw-<role> user units it installed; user-unit
       state, not configuration."

   Afterwards `nix-instantiate --parse data/bin-ledger.nix` succeeds.

2. **`.github/scripts/check-bin-ledger.py`: the loader refuses a second row.**
   In the loop at lines 445–449, before `ledger[name] = row`:
   ```python
   if name in ledger:
       die(f"{name}: two rows in the ledger; the later one would silently replace the earlier")
   ```
   `die` (line 113) prints `bin-ledger: …` and exits 1, which is the same
   way the loader already reports a bad class. The guard sits where the
   shadowing happened, so it covers every command, today's and the next
   bump's.

`checks.bin-ledger` (`tests/bin-ledger.nix`) already passes
`../data/bin-ledger.nix` and the script into its sandbox, and
`build.yml:945` builds it on every pull request. So no test wiring and no
workflow change are needed.

## Alternatives rejected

- **Evaluate the ledger in Nix** (`import ../data/bin-ledger.nix` in the
  test). Nix would catch the duplicate for free, but as an evaluation error,
  and an evaluation error aborts the whole batch of checks: every sibling
  reports "no built result" (§13). The Python guard fails only this check,
  with a message naming the command.
- **Parse-check every `data/*.nix` file.** The other ten parse today, so it
  would be a new check with nothing to guard yet.
- **Keep #1405's rows, since they are the ones in force.** Their hermes
  reason does not match the script, and their openclaw reason leaves out
  the disable.
- **Keep #1335's rows unchanged.** They are closer, but the openclaw one
  leaves out the restart, and the reason is cheap to make exact.

## Risks

- **A legitimate pattern that looks like a duplicate.** The regex matches
  every `"name" = { … };` block in the file, comments included. Today the
  only repeated names are the two being fixed, and the guard's first run
  shows whether anything else matches twice.
- **Edge.** `edge` carries the same duplicates (merged from `main`). The next
  edge run merges this from `main` cleanly, because edge's only ledger
  change, the `omarchy-apply-pacman` row at line ~156, is in a different
  hunk. If it does conflict, edge's `prepare` reports it and the fallback
  keeps edge published.
- **A CI-gate change?** No. This adds a failure condition to an existing
  check and edits no workflow, but the PR says so for the owner (§11).

## Verification

`checks.bin-ledger` builds the `omarchy` package, which is already in the
store for `main`'s pin. So it runs at the cheap tier under
`flock /mnt/data/vmtest/codex-build.lock`, after checking that both
`vm-host-free.sh` sides print `free` in case it has to build.

- **§1, red:** with the guard in and the duplicates still present (the
  guard commit before the ledger fix), the check fails with
  `bin-ledger: omarchy-install-hermes-cli: two rows in the ledger`.
- **Green:** with the ledger fixed, it passes, reporting the same row count
  as before minus two.
- **§1, second red:** add one duplicated row back to the fixed ledger, prove
  it landed with `git diff`, and watch it fail naming that command. Then
  `git checkout HEAD --` and see green again.
- `nix-instantiate --parse data/bin-ledger.nix` exits 0.
- `nix fmt -- --ci`, statix and deadnix are clean on the PR, and its CI is
  green.
