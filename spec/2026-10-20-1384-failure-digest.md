---
status: approved
issue: 1384
intent: intent/2026-10-20-1384-failure-digest.md
---

# Spec: a failed CI job ends with the failing check's name and its real error

## Design

### 1. Capture: one line in `build-unless-proven.sh`, no workflow `tee`

Every check build in `build.yml`'s `omarchy`, `system-build` and
`system-checks` jobs goes through `.github/scripts/build-unless-proven.sh`
(18 call sites). At its top, after `set -euo pipefail`:

```bash
exec > >(tee -a "${RUNNER_TEMP:-/tmp}/build.log") 2>&1
```

Its exit status is unchanged: it already ends `exit "$rc"`, and `tee` sits
outside that status.

**No workflow step gets a `| tee`.** The workflows set no `shell:`, so
`run:` steps use `bash -e` *without* pipefail, and a piped `nix build` there
would turn a red build green. The few direct `nix build` steps (for example
`omarchy` :323) are not captured. The digest finds their failures with
`nix log` (§2), which needs no capture.

The options step redirects stderr to `options-gc.txt` (build.yml
~:1646). The plan confirms the GC parse still reads that file once the
capture is in place.

### 2. `.github/scripts/failure-digest.sh [logfile]`

The script never decides pass or fail. It only prints.

1. **Failed derivations.** Collect every `error: Cannot build '<drv>'.`
   from the log file, if there is one.
2. **Cascades.** A drv whose next lines say `Reason: N dependenc(y|ies) failed`
   failed only because another did. Report it as
   `N checks failed only because <root> failed`. Only roots get an
   excerpt.
3. **Excerpt per root.** Run `nix log <drv>` and filter it with the
   patterns moved out of `.github/scripts/copilot-handoff.sh:43-48`:
   - the colour strip;
   - the `… ` / `N |` frame filter;
   - `grep -E -A6 'error|Error|FAIL|Traceback|AssertionError|RequestedAssertionFailed|does not evaluate|unexpected changes|Failed to'`;
   - `sed -n '1,40p'`, never `head` (#1157, SIGPIPE under pipefail).

   `copilot-handoff.sh` then calls the shared filter, so there is one
   pattern set.
4. **Output.**
   - Printed to stdout, so it is the last thing in the job log:
     `=== failure digest ===`, one block per root
     (`✗ <check name>` plus the excerpt), then the cascade line.
   - Appended to `$GITHUB_STEP_SUMMARY`.
   - A one-line `digest=<root names>` written to `$GITHUB_OUTPUT`.
5. **It can never fail.** `trap '…; exit 0' ERR`, and
   `continue-on-error: true` on the step. With no log and no `Cannot
   build` lines, it prints `failure digest: no failed derivation found
   in this job's build output (the failure was in a non-build step:
   see above)`, so a missing result never reads as a pass (§4).

### 3. Where it runs

A last step, `- name: Failure digest`, with `if: failure()` and
`continue-on-error: true`, in these jobs:
- `build.yml`: `omarchy`, `system-build`, `system-checks`;
- `omarchy-edge.yml`: `prepare`, `verify`.

`build.yml`'s `system` job gets the two halves' `outputs.digest` and
prints them in its existing error line:
`system-build concluded 'failure': <digest>`. No condition changes, so
it is still `!cancelled()` and still fails exactly when it does now.

### 4. Install failures are classified

`install-check.yml` already has an `if: always()` step that reads
`nix log .#checks.x86_64-linux.install` (:580-589). It gains one
classification line in its summary, by first match:

| class | signal |
|---|---|
| assertion | `AssertionError`, `RequestedAssertionFailed` |
| guest deadline | `exited 124` (`nixarchy-install`'s budget) |
| job timeout | `exceeded the maximum execution time` (the job's annotation, through `gh api …/annotations`) |
| eviction | conclusion `cancelled` with no step started |
| runner restart | conclusion `cancelled` with steps started and no timeout annotation |

The last three need the job's own conclusion, so that step runs on
`failure() || cancelled()`. That is the first step #1365 and #1260 asked
for.

## Alternatives rejected

- **`| tee` in workflow steps:** it needs `set -o pipefail` added in every
  step, and one missed spot turns a failure green.
- **Fetching `--log-failed` from the API afterwards:** slower, needs a
  token, and the log is not complete until the job ends. The owner chose
  in-job.
- **Printing the whole `nix log`:** that is the noise problem again.

## Risks

- **`exec > >(tee …)`** can lose the last lines if a job is killed. The
  digest still finds `Cannot build` drvs through `nix log`, and only the
  capture of streamed text is lost.
- **Ordering:** cachix-action's post step runs after the digest, in its
  own "Post" group, which the excerpt filter already drops.

## Verification (§1)

`checks.failure-digest`, a cheap `runCommand` over fixture logs trimmed
from real runs saved on 2026-10-20, with a stub `nix log` that serves
each fixture drv's log:

1. **A buried assertion** (from #1380's red session run: `!!! Traceback`,
   `RequestedAssertionFailed` at line ~6440 of 6452). The digest names
   `session` and shows the assertion.
2. **Passing proofs after a failure** (#1375's `omarchy` job:
   `etc-overlay` failed, then `pushing the proof of …`). It names
   `etc-overlay`, and no proof lines appear.
3. **A cascade** (#1378's `omarchy` job: `Reason: 1 dependency failed`).
   It names the one root and prints `N checks failed only because …`.
4. **No build failure.** The "no failed derivation found" line prints,
   and the script exits 0.

Each case is red against a stub digest that prints the last 25 lines,
which is today's behaviour. The `system` line is shown on a throwaway
PR with one check deliberately broken, and that commit is dropped
afterwards.
