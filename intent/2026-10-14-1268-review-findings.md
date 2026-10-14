---
status: approved
issue: 1268
author: olafkfreund
---

# Intent: fix the findings from the 2026-10-14 cross-model code review

## Problem

A read-only Codex review of the whole tree, with every claim traced against
the source, found seven defects. Two can lose data or publish a secret
without the user doing anything unusual:

1. **`nixarchy home backup` can delete a directory it did not create.**
   `NIXARCHY_HOME_BACKUP_REPO` is taken from the environment. If it names a
   directory that has files but no `.git`, the script runs `git init` in it
   (`nixarchy-home-backup:500-504`) and then deletes everything except `.git`
   (`:551`). The guard on `:550` checks for `.git`, which the script has just
   created, so it never refuses. Nothing is recoverable. A directory that is
   already a git repository, such as an existing dotfiles checkout, loses
   its uncommitted work the same way.
2. **`nixarchy config-repo` publishes a partly encrypted `secrets.yaml`.**
   The guard (`nixarchy-config-repo:406`) asks whether `ENC[AES256_GCM`
   appears anywhere in the file. One encrypted value passes the whole file,
   so a plaintext value added beside it by hand is committed and pushed.
3. **The backup follows symlinks out of its allowlist.** The home-side walk
   selects `-xtype f` (`nixarchy-home-backup:273`) and the copy dereferences
   with `cp -L` (`:562`). A link inside `~/.config/hypr` that points at
   `~/.aws/credentials` copies the credentials into the backup, and the
   credential scan only knows selected names and patterns.

Then two CI defects:

4. **`cache-budget.sh` can pass with a closure missing.** It runs under
   `set -uo pipefail` without `-e`, and nothing checks the status of the
   `nix path-info | jq` pipeline on `:45`. A failed lookup drops that entry
   from the sum and the budget reads low: a check that passes because it
   could not measure (§4).
5. **`omarchy.yml` interpolates an upstream tag into shell.** The tag only
   has to match `^v[0-9]` (`:55`) and is then pasted into `run:` with
   `${{ }}` (`:67`, `:80`). A tag such as `v5$(…)` would run in our job. This
   needs a compromised upstream or API response, but the job holds a push
   token.

And two low ones:

6. `modules/apps.nix:3484` reads `rebuild_state`'s tab-separated output with
   `IFS=$'\t' read`, which collapses empty fields: the §13 trap. systemd
   almost always fills those fields, so it rarely bites.
7. `.tar.gz` at the repository root is an empty gzip committed by accident
   in `fa6c1ec8`.

## Proposed outcome

- `nixarchy home backup` never deletes a file it did not put there: it
  refuses a non-empty directory it did not initialise, and empties only a
  repository it owns.
- `nixarchy config-repo` refuses to publish a `secrets.yaml` that has any
  value sops did not encrypt.
- The backup does not copy a file whose real location is outside the
  allowlisted trees. Links into the Nix store, which is how most of these
  configs arrive, still work.
- `cache-budget.sh` fails when it cannot measure an entry.
- The upstream tag is checked against the full version format and reaches
  the shell through `env:`, never through `${{ }}` in the script.
- `nixarchy-apply --status` reports the right fields when one is empty.
- The stray tarball is gone.

Each fix with logic in it comes with a check that fails on today's code (§1)
and passes on the fix, at the cheapest layer that can reach it.

## Affected users and systems

- Users of `nixarchy home backup` (items 1, 3), especially anyone who sets
  `NIXARCHY_HOME_BACKUP_REPO`.
- Users of `nixarchy config-repo` who keep secrets with sops (item 2).
- CI: the `system` job's cache-budget step (item 4) and the Omarchy bump
  workflow (item 5).
- `nixarchy-apply --status` and the rebuild panel that reads it (item 6).

## Constraints

- **Item 5 is a CI-gate change (§11).** The PR can propose it, but a human
  merges it. If the owner would rather keep workflow edits out of this batch, it can
  be split into its own PR.
- Item 1 must not break an existing backup repository created by today's
  script: the next run after the upgrade has to keep working.
- Item 3 must not start refusing the store-linked files a normal install
  backs up; that would make the backup fail for every user.
- `nixarchy-home-backup` and `nixarchy-config-repo` are vendored-tree
  `nix-bin` scripts. These are our own code, not upstream Omarchy, so they
  are fixed here.
- Mode A is untouched: none of this changes an option's off state.

## Open questions

1. Item 1: should the tool mark the repositories it owns (a file inside
   `.git`, written on `git init`) and refuse any other non-empty target? Or
   should it only ever remove the paths recorded by its previous commit? The
   marker is simpler. Removing only recorded paths also covers a
   user-supplied dotfiles repo, but turns "emptied first" into a diff.
2. Item 5: in this batch, or a separate PR?
3. One PR for everything, or one per group (data-loss/secrets, CI, low),
   following #1098's pattern?

## Decisions at approval

Approved by the owner on 2026-10-14 without answers to the open questions,
so the defaults are recorded here:

1. Item 1: a marker written on `git init`; any other non-empty target is refused.
2. Item 5: a separate PR, so a human-merge gate does not hold the data-loss fixes.
3. One PR for everything else.
