---
status: approved
issue: 1684
intent: intent/2026-11-08-1684-quattro-zenbook-audio.md
---

# Spec: edge adopts quattro d9cc361, classifying the Zenbook 14 audio package

## Design

### 1. The carry (intent decision 1)

One commit on `edge-candidate`, started from `origin/edge`, since the two
are equal today at `64fa36f`:

- `data/omarchy-packages.nix`, in the "Hardware this port does not target"
  block, in alphabetical order after `asus-proart-p14-speaker-firmware`:

  ```nix
  "asus-zenbook-14-ux3480qa-audio" = {
    skip = "One ASUS laptop; not targeted.";
  };
  ```

- `flake.nix`, the two values the workflow itself writes
  (`omarchy-edge.yml:244`): the input `url` carries the full 40-character
  SHA, and `omarchyVersion` becomes `edge-<YYYYMMDD>-<short sha>`, today
  `edge-20261108-d9cc361`. `checks.review-pins` reads the `edge-` prefix as
  "a revision pin" (`tests/review-pins.nix:138`). The target is `d9cc361`,
  or the newest quattro commit when the carry is made, after reading its
  diff for new install-list entries.
- `flake.lock`: `nix flake lock --update-input omarchy`, checked to name
  that rev.

Then a `from_candidate=true` dispatch of `omarchy-edge.yml` (§8: a carry
that classifies a commit pins it).

The commit message records the second decision: `fix-asus-zenbook-14-
ux3480qa-boot.sh` is a hardware install script, not a package. No ledger
reads it, and it installs nothing here.

### 2. Reconciling at the edge-to-main merge (decision 2)

CLAUDE.md §8's paragraph on the first real edge-to-main merge (#1477)
already says to rerun `readme-counts.sh --fix` against the restored pin,
because those numbers derive from it. One sentence beside it names
`checks.omarchy-package-ledger` the same way: rows for packages only quattro
has go stale under `main`'s tag pin, so drop them in that merge, or keep
them if `main` is moving to quattro. This sentence is the part of this task
that lands on `main`. It is a separate one-file PR from this branch.

## Alternatives rejected

- **Row on `main` first.** The ledger fails a row no pinned list has
  (stale, `data/omarchy-packages.nix:22-24`), so `main` would go red.
- **`module` or `nix`.** No NixOS option or nixpkgs package provides this
  model's audio fix, and the port does not target single laptop models.
- **A plain dispatch without the pin.** A scheduled run asks upstream for the
  newest commit, but a carry dispatched without the pin builds the old one,
  where the new row reads as stale (§8, #1498).

## Risks

- The ledger was the first refusal. Another check may fail on the other 19
  commits (Snapdragon fixes, NVIDIA setup removal, a translation-file read).
  The dispatched run is the measurement. A new failure is a new finding on
  #1684, not a reason to widen this carry by guessing.
- A green run proves the checks, not runtime behaviour across the other 19
  upstream commits. The nightly edge boot (`verify`) is what exercises them.
- None for `main` machines: edge only.

## Verification

- Locally, on the carry's tree (package tier, gate permitting):
  `nix build .#checks.x86_64-linux.omarchy-package-ledger`. Passes with the
  row. §1 break: the row removed fails it, naming
  `asus-zenbook-14-ux3480qa-audio`. Output in the PR comment on #1684.
- Then the cheap checks `generated-checks.sh` prints for the carry's tree,
  under the build lock.
- The dispatched `omarchy-edge` run is the confirmation. #1684 closes when
  edge has advanced, not when the carry is pushed. "Advanced" is read, not
  inferred: `git show origin/edge:flake.lock`'s omarchy `rev` equals the
  carry's target SHA. The workflow can fall back to an older pin and still
  promote (`omarchy-edge.yml:276`), and a green run on the fallback is not
  this carry landing.
- The `main` PR for section 2 changes prose only, so nothing mechanical can
  fail on its removal. It is verified by reading the sentence against intent
  decision 2 in review, plus `nix fmt -- --ci`.
