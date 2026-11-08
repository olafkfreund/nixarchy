---
status: draft
issue: 1711
spec: spec/2026-11-08-1711-nightly-digest.md
coders:
  1: codex  # the digest script: API parsing, root-finding, the cap that keeps every header, redaction; small and every branch matters
  2: coder  # the check, its stubs and fixtures, in tests/failure-digest.nix's shape: large and mechanical (agy cannot reach /mnt/data worktrees, measured on #1705)
  3: codex  # the workflow wiring: outputs, token, needs, env-only digest; small, and a slip is an injection or a silent empty digest
  4: coder  # the wiring assertions, added to step 2's check: follows its pattern
reviewers:
  - codex  # line by line against this plan
  - agy    # an independent read of the diff
---

# Plan: a nightly failure report says why, without its run

## Decisions carried from the approved intent and spec

1. **A `digest` job** in `.github/workflows/nightly.yml`, before `report`:
   `runs-on: [self-hosted, nixos, kvm, big]`; `needs:` and `if:` copied
   verbatim from `report` (`:610-631`), with a one-line pointer to
   `report`'s comment for why; `permissions: { contents: read, actions: read }`;
   `outputs: { text: ${{ steps.digest.outputs.text }} }`. Its steps:
   `actions/checkout` at `github.sha`; then a step `id: digest`,
   `continue-on-error: true`, env `GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`,
   `GH_REPO: ${{ github.repository }}`, `RUN_ID: ${{ github.run_id }}`,
   running `nix shell --inputs-from . nixpkgs#gh nixpkgs#jq nixpkgs#yq-go -c .github/scripts/nightly-digest.sh`,
   which writes `text<<DELIM … DELIM` to `$GITHUB_OUTPUT` with a random
   delimiter.
2. **`.github/scripts/nightly-digest.sh`** (new), always exits 0:
   1. `jobs=$(gh api --paginate "repos/$GH_REPO/actions/runs/$RUN_ID/jobs")`
      captured, then split (§4). Failed jobs: conclusion `failure` or
      `cancelled`, excluding `digest` and `report` themselves. For each: its
      name, its first step with conclusion `failure` or `cancelled`, and for
      `cancelled` its annotations (`gh api repos/$GH_REPO/check-runs/<job id>/annotations`):
      "exceeded the maximum execution time" reads "timed out"; otherwise
      "cancelled" plus the first annotation's message.
   2. Targets per job from the checked-out `nightly.yml` with Go `yq`: the job
      id whose `.name // key` equals the API's name; every `.#<attr>` after a
      `nix build` in its steps' `run`.
   3. Per target: `drv=$(nix eval --raw ".#<attr>.drvPath")`; roots are the
      `.drv`s in `nix-store -qR "$drv"` whose outputs
      (`nix-store -q --outputs`) are not all valid (`nix-store --check-validity`
      fails) and whose `nix log` prints something (success with empty output
      is no log). No root → the target's own `nix log` if it prints
      something, else the target is named on its own line, `<attr>: no build
      log (it never started, or it was substituted)`. Each excerpt:
      `nix log <root> | failure-excerpt.sh | tail -n 40`; if that is empty,
      the log's last 10 lines instead, as `failure-digest.sh:76` does, so a
      killed build that ended without a recognised error still shows where it
      stopped. Then redaction.
   4. Redaction, per line: a line matching `ghp_|gho_|ghs_|ghu_|github_pat_|AGE-SECRET-KEY-|-----BEGIN`
      or `[A-Z_]*(TOKEN|SECRET|PASSWORD|KEY|AUTH)[A-Z_]*=` (case-insensitive)
      becomes `[line removed: looked like a secret]`.
   5. Output: per job, `### <name>: <failed|timed out|cancelled: …> at step "<step>"`,
      then per target either its roots, each `**<drv name>**` and a fenced
      excerpt, or the target's no-log line. So every target a failed job
      names appears, even one its failed step never reached. All headers are
      written first; excerpts share the rest of 50,000 characters, each cut
      at a line boundary with "(excerpt truncated)".
   6. Any failure (the API, `yq`, an evaluation) → `digest unavailable: <what>`,
      exit 0.
   Measured for this plan (2026-11-08): re-evaluating
   `checks.x86_64-linux.install-iso-net` at that night's commit `0687162`
   gives `/nix/store/27w94zcayzw9…-vm-test-run-nixarchy-install-iso-net.drv`,
   the derivation p620 built, and `nix log` on it finds the night's log. A
   killed build's log stays readable and truncated (two 2026-10-24 installs).
3. **`report`**: `needs:` gains `digest`, its `if:` is untouched; its step's
   env gains `DIGEST: ${{ needs.digest.outputs.text }}` and
   `DIGEST_RESULT: ${{ needs.digest.result }}`; the body and the "still
   failing" comment both end with `$DIGEST`, or with
   `Digest unavailable (digest job: $DIGEST_RESULT).` when it is empty.
   `needs.digest.outputs` appears nowhere inside a `run:`.
4. Not a §11 gate change: no trigger, required check or timeout moves, and
   `report`'s condition is unchanged. A human merges the workflow edit.

## Steps

1. **The script** (`.github/scripts/nightly-digest.sh`, new, executable,
   `#!/usr/bin/env bash`, `set -euo pipefail` with an `ERR` trap that prints
   `digest unavailable: …` and exits 0, as `failure-digest.sh:12-13` does):
   decision 2 exactly.
   Verify: `bash -n`; `nix run nixpkgs#shellcheck -- .github/scripts/nightly-digest.sh`.
   Traps: `out=$(cmd) || …` never `mapfile < <(cmd)` (§4); `set -e` does not
   reach into `$(…)`, so write `x=$(f) || return` (§5); `grep -q` under
   `pipefail` (`checks.grep-q-pipefail`); `sed` not `head` mid-pipe (#1157).

2. **The check** (`tests/nightly-digest.nix` new, `tests/nightly-digest/`
   fixtures, `flake.nix` beside `failure-digest` at `:2468`), in
   `tests/failure-digest.nix`'s shape: copy the two scripts in, stub `gh`
   (serves `jobs.json` and `annotations-<id>.json` from the fixture dir;
   `STUB_GH_FAIL=1` exits 1), `nix` (`eval --raw .#<attr>.drvPath` →
   `/nix/store/<hash>-<attr-last-part>.drv` from a fixture map; `log <drv>` →
   the fixture file or exit 1), `nix-store` (`-qR`, `-q --outputs`,
   `--check-validity` from fixture lists). Run against the real
   `.github/workflows/nightly.yml`. The spec's ten cases:
   1. `install` failed at its build step, log ending in a traceback → header
      names job, step, and the excerpt has the traceback;
   2. `install-iso-net` cancelled with a timeout annotation, truncated log →
      "timed out", the log's last lines;
   3. `install-iso-net` failed at the ISO size step → job, step, and both its
      targets (`iso-budget`, `install-iso-net`) appear;
   4. `canary` failed → header only;
   5. `nix log` succeeds and prints nothing (the spec's case) → the target's
      "no build log" line;
   6. `STUB_GH_FAIL=1` → `digest unavailable:`, exit 0;
   7. four failed jobs with oversized logs → under 50,000 characters, all
      four headers present;
   8. a check whose dependency failed → the dependency's excerpt, named;
   9. cancelled with another annotation → "cancelled" and its message;
   10. log lines with `ghp_…` and `CACHIX_AUTH_TOKEN=…` → replaced.
   Every assertion prints its reason via `if … then echo FAIL…; exit 1; fi`,
   never `! grep`. Fixtures written as files under `tests/nightly-digest/`,
   not heredocs inside the `''` string (§5 nixfmt reindent).
   Verify: `nix build .#checks.x86_64-linux.nightly-digest`.

3. **The workflow** (`.github/workflows/nightly.yml`): decisions 1 and 3.
   Verify: `nix shell --inputs-from . nixpkgs#actionlint -c actionlint .github/workflows/nightly.yml`
   (the command `build.yml:183` runs).
   Traps: the copied `if:` must be byte-identical to `report`'s; no
   `${{ }}` holding the digest inside `run:`; job outputs come from
   `steps.<id>.outputs`, so the step needs `id: digest`.

4. **The wiring assertions** (`tests/nightly-digest.nix`): with Go `yq` on the
   real `nightly.yml`, assert `digest` exists with a step `id: digest` that
   runs `nightly-digest.sh`, `outputs.text` names `steps.digest.outputs.text`,
   that step's env has `GH_TOKEN`, `digest`'s `if` equals `report`'s,
   `report.needs` contains `digest`, `report`'s env carries `DIGEST`, and no
   `run:` in the file contains `needs.digest.outputs`.
   Verify: the check passes.

5. **Run, break, commit, PR** (session): cheap tier (`nightly-digest`,
   `failure-digest`, `grep-q-pipefail`, `test-registration`, actionlint,
   fmt, statix, deadnix). §1 breaks, each shown failing:
   - drop the step lookup → case 1;
   - a hard-coded target instead of `yq` → case 3's `iso-budget`;
   - cap the whole text instead of the excerpts → case 7's fourth header;
   - read only the target's own log → case 8;
   - drop the annotation lookup → case 2;
   - drop redaction → case 10;
   - remove the `|| …` guard on the jobs call **and** the `ERR` trap → case 6
     (either alone still recovers, so only both together can fail it);
   - remove `id: digest` → the wiring assertions.
   One commit per step; PR `Closes #1711` linking the three artifacts, saying
   the first failed night is the real run's proof; "@codex review"; merge
   commit.

## Tests

| check | tier | expect |
|---|---|---|
| `nightly-digest` (new) | cheap | 10 cases + wiring pass; 8 breaks fail |
| `failure-digest` | cheap | unchanged, passes |
| `grep-q-pipefail`, `test-registration` | cheap | pass |
| actionlint on `nightly.yml` | cheap | clean |

Not run locally: the job in a real failed nightly. The next "still failing"
comment on #1604 or any nightly issue is its proof.

## Rollback

Revert the PR. `report` returns to its link-only text; nothing else reads the
digest.

## Plan review

Codex (model gpt-6-sol) found four gaps, each confirmed against the files
and fixed above: the last-lines fallback for a log with no recognised error
(`failure-digest.sh:76`); a no-log line per target, since the ISO size step
precedes both builds (`nightly.yml:171-194`); the API-guard break also
disabling the `ERR` trap; case 5 restored to the spec's "prints nothing".
agy: review not obtained. `UNAVAILABLE (code 503): No capacity available for
model gpt-oss-120b-medium on the server`.
