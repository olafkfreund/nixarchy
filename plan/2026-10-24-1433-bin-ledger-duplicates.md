---
status: approved
issue: 1433
spec: spec/2026-10-24-1433-bin-ledger-duplicates.md
---

# Plan: the bin ledger holds one row per command, and its check says so

## Approved decisions

- **One row each** for `omarchy-install-hermes-cli` and
  `omarchy-install-openclaw-cli`. Keep the first pair, rewrite its
  `reason` from the scripts at `main`'s pin `03ff1eff`, and delete the
  second pair (#1405's). `class = "vendor"` and `allow = "systemctl-user"`
  are unchanged.
- **The guard** goes in `check-bin-ledger.py`'s loader: a name it has
  already stored fails with `die`.
- **No Nix evaluation of the ledger**, no `data/*.nix` parse sweep, and no
  workflow or test wiring change.

Work on `fix/1433-bin-ledger-duplicates` in `/mnt/data/vmtest/wt-1433`, cut
from `main` 6d02d181. The change is two files, below the coder hand-off
threshold, so the lead implements it.

## Steps

1. **The guard** (`.github/scripts/check-bin-ledger.py:449-450`). Replace
   ```python
               if row:
                   ledger[name] = row
   ```
   with
   ```python
               if row:
                   if name in ledger:
                       die(f"{name}: two rows in the ledger; the later one would silently replace the earlier")
                   ledger[name] = row
   ```
   Commit it as `wip: guard`.

   → verify with **§1 red**. With the duplicates still in the ledger,
     `checks.bin-ledger` fails and the log contains
     `bin-ledger: omarchy-install-hermes-cli: two rows in the ledger`.
   Traps:
   - Evaluate once (`nix eval --raw .#checks.x86_64-linux.bin-ledger.drvPath`),
     then build `"$drv^*"` (§5).
   - Run it under `flock /mnt/data/vmtest/codex-build.lock`, after
     `vm-host-free.sh install` and `vm-host-free.sh edge` both print
     `free`, in case `omarchy` is not in the store.
   - Use `set -o pipefail`, and do not pipe the build.

2. **The ledger** (`data/bin-ledger.nix`).
   - Delete lines 751–760: the second `"omarchy-install-hermes-cli"` and
     `"omarchy-install-openclaw-cli"` blocks, both braces included.
   - Set the `reason` on line 283 to: `Vendored unchanged. Stops omarchy-hermes-theme.service only after a --now set-up, before re-running the theme setter; stopping a user unit is session state and carries no configuration.`
   - Set the `reason` on line 288 to: `Vendored unchanged. Stops, disables, queries and restarts the openclaw-<role> user units it installed; user-unit state, not configuration.`
   - Run `nix fmt` and read `git diff --stat`. Expect two files changed
     across the two commits. Commit it as `wip: one row each`.

   → verify that `grep -c '"omarchy-install-hermes-cli" = {' data/bin-ledger.nix`
     and the same grep for openclaw each print `1`, that
     `nix-instantiate --parse data/bin-ledger.nix >/dev/null` exits 0, and that
     `checks.bin-ledger` is green. Its summary line reads `… rows, all true`,
     and the count is unchanged (169 on `main`). The dict already merged the
     duplicates, which is the bug, so the count never saw them.
   Traps:
   - An editor hook can reformat `.nix` files (§5), so `nix fmt` is the
     final word.
   - The `sed` for the delete must be checked with grep afterwards, because a
     `sed` that matches nothing exits 0.

3. **§1 second red.**
   - Paste a copy of the hermes block back in after the openclaw row.
   - Prove it landed with `git diff`.
   - `git add`, rebuild, and watch it go red naming
     `omarchy-install-hermes-cli`.
   - Restore it with `git checkout HEAD -- data/bin-ledger.nix`, not
     `git checkout --` (§5).
   - Check that `git status` is clean, and that the `drvPath` is step 2's
     green one.

4. **Static checks.** Run `nix fmt -- --ci`,
   `nix run nixpkgs#statix -- check .` and
   `nix run nixpkgs#deadnix -- --fail .`.
   → verify that all three exit 0.

5. **Squash and open the PR** (lead).
   - Squash the two `wip` commits into one, with the subject: "The bin ledger
     holds one row per command, and its check refuses a second (#1433)".
   - Check that `git merge-base origin/main HEAD` is 6d02d181, or the current
     `main` after a rebase, and that `git show --stat HEAD` lists only the
     two files.
   - Push, then open the PR from `.github/PULL_REQUEST_TEMPLATE.md`:
     - link the intent, spec and plan;
     - paste the step 1 and step 3 red outputs;
     - say it adds a failure condition to an existing check and edits no
       workflow;
     - use `Closes #1433`.
   - Wait for CI to go green and check that `mergeable` is `MERGEABLE`. Then
     merge with a squash and confirm that #1433 closed.

6. **Clean up.** Remove the worktree, delete the local branch (GitHub
   deletes the remote one), and delete `/mnt/data/vmtest/1433-*`.

## Tests

| step | check | expected |
|---|---|---|
| 1 | `checks.bin-ledger`, with the guard and the duplicates | red, `two rows`, naming hermes |
| 2 | `checks.bin-ledger`, with one row each | green |
| 2 | `nix-instantiate --parse data/bin-ledger.nix` | exit 0 |
| 3 | one duplicate put back | red, naming hermes |
| 4 | fmt, statix and deadnix | clean |
| 5 | the PR's CI | green |

## Rollback

Revert the squash commit. Without the guard, the old silent shadowing comes
back, and nothing else depends on this change.
