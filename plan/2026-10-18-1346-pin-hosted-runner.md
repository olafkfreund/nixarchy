---
status: draft
issue: 1346
spec: spec/2026-10-18-1346-pin-hosted-runner.md
---

# Plan: every hosted job runs on an image we chose

Approved decisions, carried from the spec:

- Pin **`ubuntu-26.04`**. Throwaway PR #1348 ran every PR-triggered hosted
  job on it and all passed; `lint` failed only because actionlint 1.7.12
  (pinned with nixpkgs) does not know the label.
- Every **functional** `ubuntu-latest` changes: 24 `runs-on:` lines (the
  `install-check.yml:329` fallback among them) and the gate's
  `runner=["ubuntu-latest"]` output at `install-check.yml:188`.
- Comments: `build.yml:1738` describes the present and is updated. The
  history comments at `install-check.yml:250` and `nightly.yml:116,425` stay
  as written.
- `.github/actionlint.yaml` declares `ubuntu-26.04`, to drop once the pinned
  actionlint knows it.
- A `lint` step, "No hosted job runs on a moving image label", fails on any
  non-comment `ubuntu-latest` under `.github/workflows/`.
- This is a CI-gate change (§11): a maintainer merges the PR.

The change touches more than three files, so the `coder` agent implements it
(managed instructions, model split); the lead commits and opens the PR.

## Steps

1. **`.github/workflows/*.yml`: pin the image.**
   `sed -i -E '/^[[:space:]]*#/!s/ubuntu-latest/ubuntu-26.04/g' .github/workflows/*.yml`
   then edit the comment at `build.yml:1738` by hand: "ubuntu-latest runners
   have /dev/kvm" → "ubuntu-26.04 runners have /dev/kvm".
   → verify: `grep -rn 'ubuntu-latest' .github/workflows/` prints exactly
   `install-check.yml:250`, `nightly.yml:116` and `nightly.yml:425`, all
   comments; `grep -rc 'ubuntu-26.04' .github/workflows/ | awk -F: '{s+=$2} END {print s}'`
   prints 26 (24 runs-on, the `:188` output, the `:1738` comment).
   Traps: the `:329` line is a `${{ }}` expression with the label as a quoted
   string, which the sed handles; check it by eye. `git diff --stat` lists
   only workflow files.

2. **`.github/actionlint.yaml`: declare the label.** Add at the end:

   ```yaml
   # A GitHub image, not one of ours: actionlint 1.7.12 predates the label
   # (#1346). Drop this once the pinned actionlint knows ubuntu-26.04.
   - ubuntu-26.04
   ```

   as a fourth entry under `self-hosted-runner.labels` (the comment indented
   with the list).
   → verify: `nix shell --inputs-from . nixpkgs#actionlint -c actionlint -ignore 'SC[0-9]+:(info|style):'`
   exits 0. Run it under the build lock (§6 cheap tier).
   Traps: none.

3. **`.github/workflows/build.yml`, `lint` job: the guard.** Insert it directly
   after the "The workflow files are valid GitHub Actions" step (around
   `:181–184`), before the nightly-watchdog comment block:

   ```yaml
      # A moving label lets GitHub change the image under a job for a month
      # of mixed runs (#1346). The pattern is split so this step cannot match itself.
      - name: No hosted job runs on a moving image label
        run: |
          if grep -rnE 'ubuntu-''latest' .github/workflows/ | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; then
            echo "::error::the lines above run on a moving image label; pin a version such as ubuntu-26.04 (#1346)"
            exit 1
          fi
   ```

   → verify: step 4.
   Traps: indentation must match the sibling steps (6 spaces before `- name`).
   `nix fmt` does not touch YAML; re-run actionlint after this step.

4. **Break proof (§1), under bash, as a script.** Write
   `/mnt/data/vmtest/wt-1346-guard.sh` with `#!/usr/bin/env bash`, which
   extracts the step's `run:` body from `build.yml` with `yq` (or copies the
   three lines verbatim) and runs it in the worktree root.
   - Clean tree: exits 0.
   - Break: `sed -i '0,/runs-on: ubuntu-26.04/s//runs-on: ubuntu-latest/' .github/workflows/weekly.yml`;
     confirm with `git diff` that the break landed; run it: exits 1 and prints
     `weekly.yml:36`.
   - Restore with `git checkout HEAD -- .github/workflows/weekly.yml` (after
     committing steps 1–3, so HEAD holds the fix); exits 0.
   - A comment line naming the label (`install-check.yml:250`) is present
     throughout, so the clean run also proves comments are excluded.
   Capture both outputs for the PR.
   Traps: `git checkout --` restores the index, not HEAD (§5).

## Tests

- actionlint as above: exit 0.
- The `grep` counts in step 1.
- The guard's red/green pair in step 4.
- The PR's own run: every job green; logs show `Image: ubuntu-26.04`.

## Rollback

Revert the squash commit. The image label goes back to `ubuntu-latest` and the
guard and the actionlint entry go with it; nothing outside `.github/` changes.
