---
status: draft
issue: 1684
spec: spec/2026-11-08-1684-quattro-zenbook-audio.md
coders:
  1: codex  # three exact edits in two files, where a wrong pin format fails review-pins
  3: codex  # one sentence in CLAUDE.md, placed beside an existing paragraph
reviewers:
  - codex  # the carry is small enough to check line by line against this plan
  - agy    # an independent read of the same diff
---

# Plan: edge adopts quattro d9cc361, classifying the Zenbook 14 audio package

## Decisions carried from the approved spec

1. The row is `skip = "One ASUS laptop; not targeted.";`, matching
   `asus-proart-p14-speaker-firmware`.
2. The row lives only in an `edge-candidate` carry. On `main`, the ledger
   would fail it as stale (`data/omarchy-packages.nix:22-24`), because
   `main` pins v4.5.0.
3. The carry also pins the commit (CLAUDE.md §8). The input `url` gets the
   full SHA, and `omarchyVersion` gets `edge-<YYYYMMDD>-<short sha>`
   (`omarchy-edge.yml:244`). Then a `from_candidate=true` dispatch.
4. The commit message records that `fix-asus-zenbook-14-ux3480qa-boot.sh` is
   a hardware script, not a package, and installs nothing here.
5. "Landed" means `origin/edge:flake.lock` names the target rev, not that a
   run was green: the workflow can fall back to an older pin
   (`omarchy-edge.yml:276`).
6. On `main`, one sentence in CLAUDE.md §8 beside the #1537 paragraph
   (line 987) names the package ledger alongside readme counts for the
   edge-to-`main` merge.

## Steps

1. **The carry's edits** (worktree `/mnt/data/vmtest/wt-1684-edge`, made by
   `git worktree add --detach /mnt/data/vmtest/wt-1684-edge origin/edge-candidate`,
   then `git switch -c carry-1684`; `edge-candidate` equals `edge` at
   `64fa36f` today, and if `edge-candidate` is behind `edge`, start from
   `origin/edge`). Before editing, list quattro commits after `d9cc361`
   (`gh api repos/basecamp/omarchy/commits?sha=dev`). If newer ones exist,
   read their `install/*.packages` diff and take the newest as the target.
   - `data/omarchy-packages.nix`: after the `asus-proart-p14-speaker-firmware`
     row (lines 483-485), add the row from decision 1.
   - `flake.nix:82`: `url = "github:basecamp/omarchy/<full target sha>";`
   - `flake.nix:436`: `omarchyVersion = "edge-20261108-<short sha>";`

   Verify: `git diff` shows exactly those three hunks, with no other line
   touched.
   Traps: §5, a `.nix` edit can come back reformatted by an editor hook, so
   run `nix fmt` and read `git diff --stat`. The short SHA has 7 characters
   (the same format as the line it replaces).

2. **Lock, prove, commit** (session):
   - `nix flake lock --update-input omarchy`. `jq -r .nodes.omarchy.locked.rev flake.lock`
     must equal the target.
   - Package-tier gate (§6): no p620 system build, load below 12,
     `vm-host-free.sh install` and `edge` both print `free`. Then
     `nix build .#checks.x86_64-linux.omarchy-package-ledger`: pass.
   - §1: remove the row, rebuild, and capture the failure naming
     `asus-zenbook-14-ux3480qa-audio`. Restore with `git checkout HEAD --`
     after committing, never from the index (§5).
   - The cheap checks `generated-checks.sh` prints, under
     `flock /mnt/data/vmtest/codex-build.lock`.
   - Commit, with a message that carries decision 4. Fast-forward push to
     `edge-candidate` (it equals `edge`, so this is no rewrite; if it has
     moved, rebase the carry onto it, never force). Dispatch
     `gh workflow run omarchy-edge.yml -f from_candidate=true`.

   Verify: the run ends, and then `git show origin/edge:flake.lock` names the
   target rev (decision 5). A different failure in that run is a new finding,
   posted on #1684, not a reason to widen this carry.

3. **The `main` sentence** (this branch, `carry/1684-quattro-zenbook-audio`):
   after CLAUDE.md:987 (the #1537 paragraph ends "neither side's README is
   right for the other (#1537)."), add:

   > The package ledger is pin-derived too: a `data/omarchy-packages.nix` row
   > for a package only quattro installs goes stale under `main`'s tag pin,
   > so drop it in that merge, or keep it if `main` is moving to quattro.

   Verify: the sentence matches decision 6, `nix fmt -- --ci` passes, and
   `git diff --stat` shows CLAUDE.md alone. CLAUDE.md is a symlink to
   AGENTS.md, so the diff names `AGENTS.md`.
   Traps: §9 section numbering is cross-referenced, so this adds no section.

## Tests

| check | expect |
|---|---|
| `checks.omarchy-package-ledger` on the carry | pass. Fails without the row (§1 output in the #1684 comment) |
| generated cheap checks on the carry | pass |
| dispatched `omarchy-edge` run | edge's lock names the target |
| `nix fmt -- --ci` on `main`'s PR | pass |

## Rollback

On edge, the next scheduled run starts from `edge` and drops a carry that
has not landed. A landed carry is reverted by a carry that restores
`6194f46` and removes the row. On `main`, revert the one-sentence PR.

## PR notes

- `main` PR: one sentence, `Refs #1684` (the issue closes when edge
  advances). The branch carries the intent, spec and plan history, so it
  merges with a merge commit: `--auto --merge --delete-branch`.
- Comment "@codex review" on the PR.
