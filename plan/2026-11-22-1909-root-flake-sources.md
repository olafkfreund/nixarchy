---
status: draft
issue: 1909
spec: spec/2026-11-22-1909-root-flake-sources.md
coders:
  1: claude   # small and tricky: the failure handling is the point; the session writes it
  2: claude   # the check must be proven to fail seven ways, which the session runs
  3: claude   # 12 one-line YAML insertions; mechanical, but a CI-gate change the session owns
reviewers:
  - codex     # second read on nix GC semantics
  - agy       # second read on the workflow call sites
---

# Plan: a self-hosted job keeps its own flake source alive through the host's auto-GC

## Approved decisions, from the spec

- **Cause.** Nightly run 44979123567's repush job, on p620-nixarchy-2, triggered nix's auto-GC because free space was below `min-free = 100 GiB`. The GC deleted the job's own flake source `/nix/store/3b0k…-source`, which no root held. Evaluation then failed with `path … is not valid`.
- **Script.** `.github/scripts/root-flake.sh <dir>`:
  1. `mkdir -p <dir>`;
  2. `out=$(nix flake archive --json .) || die`, never `< <(…)`;
  3. `jq -r '[recurse(.inputs[]?) | .path? | strings | select(startswith("/nix/store/"))] | unique | .[]'`, refusing a missing top-level `.path` or fewer than two paths;
  4. `nix-store --add-root <dir>/<n> --realise <path>` for each path;
  5. verify every path with `nix-store --check-validity` and every link in `nix-store --gc --print-roots`, re-running from 2 at most three times, then failing with the path's name;
  6. print the count.
- **`$RUNNER_TEMP`.** On p620 it is `/run/github-runner/<name>/_temp`, the runner unit's `RuntimeDirectory`, visible to the daemon.
- **Call sites.** A step right after `actions/checkout` in 12 jobs:
  - `nightly.yml`: install, install-encrypted, keyboard-boot, microvm, install-iso-net, repush, digest;
  - `omarchy-edge.yml`: verify;
  - `weekly.yml`: install-stock-iso, stable-session;
  - `release.yml`: iso;
  - `install-check.yml`: install.

  The step:

  ```yaml
  - name: Root this flake's source and inputs for the job (#1909)
    run: nix shell --inputs-from . nixpkgs#jq -c .github/scripts/root-flake.sh "$RUNNER_TEMP/flake-roots"
  ```

  On `digest` it also carries `continue-on-error: true`, so a rooting failure cannot suppress the digest.
- **`checks.root-flake`.** A stubbed script half, and a coverage half that fails, naming the job, when any job whose `runs-on` is not a literal `ubuntu-*` label has a checkout not immediately followed by a step running `root-flake.sh`.
- **Out of scope.**
  - The host's `min-free` policy, which lives in the config repo and is the owner's call.
  - `--no-link` outputs between two commands, and paths fetched outside `flake.lock` (IFD, `builtins.fetch*`). Both fail loudly; the spec records them.
- **Merging.** This is a CI-gate change (§11), so the PR stays open for the owner.

## Steps

1. **`.github/scripts/root-flake.sh`** (new, executable, `#!/usr/bin/env bash`, `set -euo pipefail`): the six behaviours above.
   - Verify: `bash -n`, shellcheck, and `checks.grep-q-pipefail`.
   - Traps: `set -e` does not reach inside `$(…)` (§5), a process substitution's status is lost (§4), and verification runs under bash (§1).
2. **The script half of `tests/root-flake.nix`** (new), plus `checks.root-flake` in `flake.nix` next to `proof-push`.
   - Stub `nix`: prints a fixture tree with a source, two inputs, a nested input, and an input *named* `path`. It can instead print that same valid tree and exit 1, or print a tree with inputs but no top-level `.path`.
   - Stub `nix-store`: records `--add-root` and fails if the root's directory is missing. It answers `--check-validity` and `--print-roots` from its record, and has modes for one path invalid once, one path always invalid, one link missing from `--print-roots` once, and one missing always.
   - Assertions:
     - every fixture path is rooted, and nothing else;
     - a failing archive exits non-zero, with nothing rooted;
     - an archive with no top-level `.path` is refused;
     - a no-input archive is refused;
     - an invalid-once path and an unlisted-once link are retried and pass;
     - an always-invalid path and an always-unlisted link fail, each naming the path.
   - Verify: `git add`, then `nix build .#checks.x86_64-linux.root-flake` passes.
   - Traps: in a `''` string, `''${` escapes and `\$` is literal (§5); avoid heredocs that make nixfmt reindent (§5).
3. **The 12 call sites**, each with the YAML above, including `continue-on-error: true` on `digest`. In edge's verify, the step goes after the candidate checkout.
   - Verify: actionlint (`nix run nixpkgs#actionlint`).
4. **The coverage half** of `tests/root-flake.nix`: Python with PyYAML over `.github/workflows/*.yml`. It is added only now that step 3 has made the workflows pass.
   - Verify: `nix build .#checks.x86_64-linux.root-flake` passes.
5. **Red proofs** (§1). For each break: make the break, confirm it landed with `git diff`, build the check and watch it fail with a readable message, restore with `git checkout HEAD -- <file>`, and watch it pass again.
   1. The walk becomes `[.. | objects | .path? // empty] | unique | .[]`. The input named `path` is then emitted as an object and rooted, so "nothing else" must fail.
   2. The archive is read as `mapfile -t paths < <(nix flake archive --json . | jq …)`. The exit-1 valid tree is then accepted, so "failing archive" must fail.
   3. The fewer-than-two refusal is removed, so "no-input archive" must fail.
   4. The top-level `.path` refusal is removed, so "no top-level path" must fail.
   5. The `--check-validity` check is removed, so "always-invalid" must fail.
   6. The `--print-roots` check is removed, so "always-unlisted" must fail.
   7. The step is removed from `nightly.yml`'s repush job, so coverage must fail, naming `nightly.yml: repush`.
6. **A sentence in CLAUDE.md §4**, appended to the existing bullet "A path in the cache is not a path that stays there". A path in the store is not one that stays there during a job either, when the host auto-GCs. The bullet is extended, not added, so nothing is renumbered.
   - Verify: read the diff.

## Tests

- `checks.root-flake` passes, and each of the seven breaks in step 5 fails it, then passes again once restored.
- Every generated check builds (`.github/scripts/generated-checks.sh`), under the build lock.
- `nix fmt -- --ci`, statix and deadnix are clean.
- By hand on p620:
  1. `.github/scripts/root-flake.sh /mnt/data/vmtest/flake-roots` roots every path;
  2. `nix-store --delete <source>` refuses while the roots exist;
  3. after `rm -r` of the directory, the delete succeeds;
  4. `nix flake archive .` puts the source back.
- After merge, which is the owner's: `gh workflow run nightly.yml --ref main`. Confirm in that run that the root step ran and passed in every self-hosted job that ran. #1909 closes only after a nightly whose `repush` job actually ran the step and passed.

## Rollback

Revert the PR. The roots are indirect and per-job, so nothing outlives a run.
