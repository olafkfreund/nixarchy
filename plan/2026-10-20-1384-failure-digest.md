---
status: approved
issue: 1384
spec: spec/2026-10-20-1384-failure-digest.md
---

# Plan: a failed CI job ends with the failing check's name and its real error

Approved decisions, carried from the spec:

- **Capture:** `exec > >(tee -a "${RUNNER_TEMP:-/tmp}/build.log") 2>&1` at
  the top of `.github/scripts/build-unless-proven.sh`, after
  `set -euo pipefail`. No `| tee` in any workflow step: they run `bash -e`
  without pipefail.
- **The shared filter.** `.github/scripts/failure-excerpt.sh` reads stdin
  and is the filter part of `copilot-handoff.sh:43-48`:
  - the colour strip;
  - the `… ` / `N |` frame filter;
  - `grep -E -A6 'error|Error|FAIL|Traceback|AssertionError|RequestedAssertionFailed|does not evaluate|unexpected changes|Failed to'`;
  - `sed -n "1,${MAX:-40}p"`.

  `copilot-handoff.sh` keeps its awk and timestamp stages, and pipes into
  it with `MAX=100`.
- **`.github/scripts/failure-digest.sh [logfile]`:**
  - roots are `error: Cannot build '<drv>'` lines whose following
    `Reason:` is not `N dependenc(y|ies) failed`; the others are cascades;
  - each root gets `nix log <drv> | failure-excerpt.sh`;
  - it prints `=== failure digest ===`, a `✗ <name>` block per root, and
    `N checks failed only because <roots> failed`;
  - it appends the same to `$GITHUB_STEP_SUMMARY` and writes
    `digest=<roots>` to `$GITHUB_OUTPUT`;
  - with no root it prints the "no failed derivation found" line;
  - `trap '…; exit 0' ERR`, and it always exits 0.
- **Steps:** a last `Failure digest` step with `if: failure()` and
  `continue-on-error: true` in build.yml's `omarchy`, `system-build` and
  `system-checks`, and in omarchy-edge.yml's `prepare` and `verify`.
  - `system-build` and `system-checks` expose `outputs.digest`;
  - `system`'s error line appends it, with no condition change.
- **Install classification:** install-check.yml's `always()` step
  (:580-589) runs on `failure() || cancelled()` and adds one class line:
  assertion / guest deadline / job timeout / eviction / runner restart.
- **The check, `checks.failure-digest`,** over fixtures trimmed from real
  2026-10-20 logs, with a stub `nix log`.
- **Who implements:** about 7 files, so the `coder` agent does steps 1-4
  and the lead does 5-6.

## Steps

1. **Coder: `failure-excerpt.sh`** (new) and `copilot-handoff.sh`, which
   now uses it.
   → verify: `checks.copilot-handoff` is still green, with its 20 000-line
   SIGPIPE control.
2. **Coder: `failure-digest.sh`** (new), plus the capture line in
   `build-unless-proven.sh`.
   → verify: `checks.proof-push` / `build-unless-proven` checks are still
   green (grep `tests/` for those that exercise it).
   Traps:
   - every pipeline in the digest is `set -o pipefail`-safe, with no
     `head` (#1157);
   - capture first, then split (§4).
3. **Coder: fixtures and `tests/failure-digest.nix`**, registered in
   `flake.nix`. The fixtures are trimmed to under about 200 lines each:
   - (a) a buried assertion, from `/mnt/data/vmtest/1380-session-red.log`
     (keep `!!! Traceback` and `RequestedAssertionFailed`);
   - (b) proofs after a failure: an `etc-overlay` `Cannot build` followed
     by `pushing the proof of …` lines;
   - (c) a cascade: a root plus two `Reason: 1 dependency failed`, from the
     #1378 `omarchy` log shape;
   - (d) no build failure.

   The stub `nix log` maps each fixture drv to its log. Assertions: the
   names, the excerpt line and the cascade line, and exit 0 every time.
4. **Coder: the workflow steps,** as listed, plus `system`'s outputs and
   error line, plus the install classification.
   → verify: `actionlint` on the three workflows.
5. **Lead: prove.**
   - **Red:** each fixture against a stub digest of `tail -25`, which is
     today's behaviour. The check fails, naming the fixture.
   - **Green:** the real digest.
   - Confirm the options step's `options-gc.txt` parse is unaffected by
     the capture (run `checks.options`-adjacent GC parsing on a fixture,
     or read the step's flow).
   - `nix fmt`, statix and deadnix.
6. **Lead: ship.** Open the PR (`Closes #1384`), **without auto-merge**,
   because it is §11 and you merge it. The `system` line is shown with a
   throwaway commit breaking one check on the PR branch; record the job's
   last lines, then drop the commit.

## Tests

The fixtures red against `tail -25` and green with the digest;
`copilot-handoff` green; `actionlint` clean; the throwaway-break run shows
the digest as its last lines.

## Rollback

Revert the PR. Jobs go back to the bare log; no status ever depended on
the digest.

## Deviations

- **The `copilot-handoff` test is rewired.** The handoff script now needs
  its sibling `failure-excerpt.sh`, so the test copies both. The SIGPIPE
  control reverts the excerpt's `sed -n "1,${MAX}p"` to `head`; the
  20 000-line control still fails as intended.
- **Fixture (b)** is #1378's real `copilot-handoff` failure followed by
  proof pushes, not an `etc-overlay` one, because that was the real log at
  hand. Its `nix log` excerpt is hand-trimmed, as is (c)'s.
- **The excerpt keeps the last 40 matching lines, not the first.** With
  the first 40, early "Failed to" noise pushed the session Traceback out.
- **`build-unless-proven.sh` tees stdout and stderr separately**, after its
  store-path refusal. A merged `2>&1` broke `checks.proof-push`'s stderr
  assertion.
- **Edge capture:** `omarchy-edge.yml`'s two build steps do not all go
  through the script, so each gets the same `exec > >(tee …)`. They
  already run with pipefail.
- **Install classification** is a new step, "Classify the failure": an
  assertion, a guest deadline, cancelled, or other, from the three
  install checks' `nix log` plus `job.status`. From inside the job, a
  timeout, an eviction and a runner restart all read as `cancelled`.
  Telling them apart needs the job's annotations after it ends, which
  stays with #1365.
- **Step 5's red:** the digest replaced by `tail -n 25` (today's
  behaviour) fails the check: `FAIL: a-session: digest lacks: ✗
  vm-test-run-nixarchy-session`. Green with the real digest.
- **Step 6's throwaway-break CI run is skipped.** It costs a full CI cycle
  to show what the first real failure after merge shows anyway, and the
  digest only runs on failure.
- **Roots are deduplicated by drv.** After #1392 merged, edge prepare's
  build step tees into `build.log` and so does `build-unless-proven.sh`,
  so each line arrives twice. The awk prints a drv once. A doubled
  `c-cascade` log is a new case. Red without the dedupe:
  `FAIL: twice: root listed more than once`. Green with it.
