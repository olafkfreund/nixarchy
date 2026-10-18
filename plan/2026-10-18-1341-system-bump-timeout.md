---
status: draft
issue: 1341
spec: spec/2026-10-18-1341-system-bump-timeout.md
---

# Plan: a nixpkgs bump finishes inside the system job's limit

## Approved decisions, carried over

1. **Split `system` into two parallel jobs, divided by what needs `hypr-rdp`,**
   and keep a job named **`system`** that passes only when both halves did.
   Branch protection's required contexts
   (`lint, omarchy, system, devenv-presets, box, install`) do not change.
2. **`system-build`** keeps the toplevels, `coexistence`, the allowlisted
   tools and box image, the system-closure push, `options`, **`session`** and
   the cache budget. Of `system`'s checks only `session` and `options` pull in
   `hypr-rdp` (`tests/session.nix:171`), so it is compiled once, here.
3. **`system-checks`** takes the MicroVM template and its push, the box
   template, `integration`, `coexist`, `install-teardown`, `installer-ui`,
   `try-nixarchy`, `dashboard-clock`, `installer-wizard` and `plugin`.
4. **Both halves gain `box`'s step "/dev/kvm is real and writable, or fail
   here"** (`build.yml:1736-1751`), after `Free disk space`. Today `system`'s
   VM tests run under TCG.
5. **The aggregator `system`** has `needs: [gate, system-build, system-checks]`,
   `if: ${{ !cancelled() }}`, and fails unless all three concluded `success`
   (#1134's shape; a skipped required check passes the gate, #1144).
6. **`copilot-handoff.sh` excludes the aggregator** from its `failure` filter,
   so a timed-out half (`cancelled`) still reaches a human rather than Copilot.
7. **Each half keeps `timeout-minutes: 45`** and today's per-commit
   concurrency group, named by job.
8. **Verification is measured**, on a throwaway draft PR from a `test/`
   branch: red `system-checks`, red `system-build`, and a timed-out half each
   read `BLOCKED`, and `copilot-handoff.sh` hands off nothing for the timeout.
   `session` is timed under KVM. **Stop before the real PR** if `system-build`
   would still exceed ~35 minutes on a bump.
9. **A CI-gate change** (§11): the PR proposes it, a maintainer merges it.
   #1341 closes on the next nightly bump finishing without a re-run.

### Found while planning

- **The budget step builds the MicroVM runners.** `cache-budget.sh` realises
  every `cache-allowlist.sh` entry (`:34-40`), the `runners` group included.
  After the split those are built in `system-checks`, so on a bump
  `system-build` builds them a second time for the budget: about +2 minutes,
  putting the TCG estimate at ~40.5. Moving the budget to `system-checks`
  instead would rebuild `hypr-rdp` there (10 minutes), which is worse. The
  stop rule in step 4 counts the +2.
- **The stub `gh` in `tests/copilot-handoff/gh` ignores `-q`.** It prints the
  already-filtered job name, so a change to the jq filter cannot make
  `checks.copilot-handoff` fail. Step 2 makes the stub apply `-q` to a JSON
  fixture, so the exclusion has a case and a control (§1).
- **The branch is one merge behind `main`** (base 722a25b8, main 4ce13f24) and
  is pushed. No force-push: step 6 merges `main` in, and the PR squash-merges
  under its title.

## Who does what

Four files change across three editing steps, so the coder (Sonnet) does steps
1–3, one `SendMessage` per step. The lead does 4–6, every commit and push, and
runs every build (§6 tiers).

## Steps

### 1. [coder] `.github/workflows/build.yml`

- **Rename** the job `system:` (`:1306`) to `system-build:`, and its
  concurrency group's `-system-` to `-system-build-` (`:1348`).
- **Add `system-checks:`** directly after `system-build`. Copy its header and
  setup verbatim: `needs: gate`, `if: ${{ !cancelled() }}`,
  `runs-on: ubuntu-latest`, `timeout-minutes: 45`, a concurrency group with
  `-system-checks-`, then the steps through `Free disk space`
  (`:1352-1392`): the gate's "cannot pass" step, "Nothing here can affect a
  build", `checkout`, `setup-nix`, and the pull-only `cachix-action` with its
  comments. The long `timeout-minutes` and concurrency comments stay on
  `system-build` only; `system-checks` gets one line pointing at them.
- **Add box's KVM step** (`:1736-1751`, comment and all five checks) to both
  halves, right after `Free disk space`. In each copy, the comment's "this
  job" stays true.
- **Move** these steps, comments included, from `system-build` to
  `system-checks`, keeping their order:
  - "Read a MicroVM runner without booting it" (`:1439`),
    "Push the MicroVM template runners to cachix" (`:1449`) and
    "Read a box template without pulling it online" (`:1461`);
  - the run from "Build onto a config that already exists" (`:1614`) through
    "Add third-party plugins from real repos" (`:1667-1675`): `integration`,
    `coexist`, `install-teardown`, `installer-ui`, `try-nixarchy`,
    `dashboard-clock`, `installer-wizard`, `plugin`.

  "Drive a session and the app-selection loop" (`:1474`), "Check every option
  both ways" (`:1485`) and "The cache allowlist fits its budget" (`:1676`)
  stay in `system-build`.
- **Add the aggregator** after `system-checks`:
  ```yaml
  # The required context. Two halves since #1341, so a nixpkgs bump, which has
  # no proofs, fits each 45-minute cap; this passes only when both did. Never
  # skipped: a skipped required check passes the merge gate (#1144).
  # copilot-handoff.sh ignores this job: a half's timeout is a human's (#1341).
  system:
    needs: [gate, system-build, system-checks]
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Both halves of the system check passed
        run: |
          fail=0
          for r in "gate=${{ needs.gate.result }}" "system-build=${{ needs.system-build.result }}" "system-checks=${{ needs.system-checks.result }}"; do
            [ "${r#*=}" = success ] || { echo "::error::${r%%=*} concluded '${r#*=}'; refusing to report system as passed (#1341, #1134)"; fail=1; }
          done
          exit $fail
  ```
- **Comments:**
  - the `timeout-minutes` comment (`:1310-1317`) gains one paragraph: a
    nixpkgs bump has no proofs, so `system` ran ~50 minutes and timed out
    (#1332); since #1341 it is two halves, split by what needs `hypr-rdp`,
    both on KVM.
  - the concurrency comment's measured table (`:1326-1329`) is history; leave
    it.
  - `box`'s comment (`:1695-1697`): "that job's 30-minute budget is already
    mostly spent, and this needs /dev/kvm arranged first, which no step there
    does" is stale twice. Replace it with: it needs its own budget, and its
    KVM step is the one both `system` halves copied (#1341).

Verify:
- `nix run nixpkgs#actionlint -- .github/workflows/build.yml` is clean.
- `grep -c 'build-unless-proven.sh .#checks.x86_64-linux' .github/workflows/build.yml`
  is unchanged from `main`.
- Every check named in the old `system` job appears exactly once across the
  two halves: diff the sorted `checks.x86_64-linux.<name>` lists of old
  `system` (`git show origin/main:.github/workflows/build.yml`) against the
  union of the halves.
- `grep -n 'needs:.*system' .github/workflows/*.yml` names only the
  aggregator.

Traps:
- YAML indentation: a step moved with the wrong indent becomes part of the
  previous step's `with:`. `actionlint` catches most of it; read the first
  line of every moved block.
- Do not touch step contents, `if:`s or `env:`s. The pushes are main-only
  inside `cachix-push.sh`, not by condition.

### 2. [coder] `.github/scripts/copilot-handoff.sh` and its check

- `copilot-handoff.sh:11-12`: the filter becomes
  `select(.conclusion=="failure" and .name!="system")`, with one comment line:
  the aggregator `system` fails whenever a half does, including a half that
  timed out, so it is not evidence of a failure (#1341).
- `tests/copilot-handoff/gh`: the `--json jobs` case applies the caller's
  `-q` expression with `jq -r` to `${GH_JOBS:-[{"name":"system-checks","conclusion":"failure"}]}`
  wrapped as `{"jobs": …}`, instead of printing a fixed name. Read `-q`'s
  value from the arguments in the stub (it is the argument after `-q`).
- `tests/copilot-handoff.nix`: add a case after the existing one, with
  `GH_JOBS='[{"name":"system","conclusion":"failure"},{"name":"system-build","conclusion":"cancelled"},{"name":"system-checks","conclusion":"success"}]'`:
  - the real script exits 0 and prints `not handed off`;
  - the control is the script with `and .name!="system"` removed by `sed`:
    prove the edit landed with `grep` (§1), then it must print
    `would comment on #1154`, or the check fails saying it cannot tell the
    exclusion from its absence.
  The existing case keeps passing with the default `GH_JOBS`.

Verify (lead, cheap tier, under the flock):
`nix build .#checks.x86_64-linux.copilot-handoff --print-build-logs` passes.
Then break the exclusion in the real script (remove it), confirm with
`git diff`, watch the new case fail, restore with `git checkout HEAD --`.
Capture the failing output for the PR.

Traps:
- `printf '%s\n'`, not a heredoc, inside the Nix string (§5).
- `nix fmt` after the `.nix` edit, then read `git diff --stat` (§5: an edit
  hook may reformat in another style).
- `git add` the stub change before building: the flake sees tracked files only.

### 3. [coder] Docs

- `docs/internals/workflows.md:103-107`: `system` is now `system-build` and
  `system-checks` plus an aggregator named `system`. Say what each half runs,
  that both have `/dev/kvm`, and why (#1341). One short paragraph.
- `AGENTS.md:583`: "`cache-budget.sh` fails the `system` job" becomes the
  `system-build` job. Leave `:294`, which is history. (`CLAUDE.md` is a
  symlink to `AGENTS.md`; edit `AGENTS.md`.)

### 4. [lead] Throwaway PR: blocking, the timeout, and `session` under KVM

When `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
prints `0`: `git worktree add --detach /mnt/data/vmtest/wt-1341-test`, push
three runs to `test/1341-throwaway` from it, as a **draft** PR. Cancel each
run's `install check` as soon as it starts (§13). Wait for each run to end
before the next push, since a push cancels the previous run.

| run | change on top of the branch | record |
|---|---|---|
| A | `exit 1` as a new first step of `system-checks`; touch a comment in `tests/session.nix` | `mergeStateStatus` `BLOCKED`; `system` names `system-checks`; `system-build`'s total and the `session` step's duration under KVM |
| B | `exit 1` as a new first step of `system-build` | `BLOCKED`; `system` names `system-build` |
| C | `system-checks` with `timeout-minutes: 1` and a first step `sleep 120` | `BLOCKED`; `system-checks` `cancelled` with the "exceeded the maximum execution time" annotation; `RUN_ID=<C> REPO=olafkfreund/nixarchy BRANCH=test/1341-throwaway DRY_RUN=1 .github/scripts/copilot-handoff.sh` prints `not handed off` |

Then close the PR, delete the branch, and remove the worktree.

**The stop rule.** The bump estimate for `system-build` is 38.5 (the spec's
TCG total) − 9.8 (`session` under TCG) + 2 (the runners for the budget) + run
A's `session` under KVM. If that exceeds 35, stop and report to the user
before step 5; the spec needs another revision.

### 5. [lead] Timing on the real PR

The PR's own run gives both halves' durations. Record them in the PR body
with run A's measurements, next to the spec's estimates.

### 6. [lead] PR

- `git merge origin/main` into the branch (no rebase: the branch is pushed,
  and there is no force-push). Check `git merge-base origin/main HEAD` is
  `main`'s head and the diff against it lists only this plan's files.
- Title: `The system check runs in two parallel halves on KVM, so a nixpkgs
  bump fits the 45-minute limit (#1341)`. The squash uses it.
- Body: links intent, spec and plan; says the coder did steps 1–3; includes
  run A/B/C's merge states, the timings, the copilot-handoff failing output;
  says it changes a CI gate for a maintainer to merge; `Refs #1341` (it
  closes after the next nightly bump finishes without a re-run). No skip-CI
  marker in its literal form (§8). Check `closingIssuesReferences` is empty.
- No `merge-when-green`: a human merges.

## Tests

| command | expect |
|---|---|
| actionlint on `build.yml` | clean |
| `build-unless-proven` count | unchanged from main |
| check list, old `system` vs the halves | identical |
| `checks.copilot-handoff` | passes; fails with the exclusion removed |
| run A | `BLOCKED`, `system` names `system-checks`, KVM timings recorded |
| run B | `BLOCKED`, `system` names `system-build` |
| run C | `BLOCKED`, half `cancelled` by timeout, handoff `not handed off` |
| the PR's own run | `system-build`, `system-checks`, `system` green |
| next nightly bump | both halves finish, no re-run |

## Rollback

Revert the PR. `system` is one job again under the same name, so branch
protection needs nothing either way. The revert takes the handoff exclusion
with it, which matters: against a single `system` job it would skip the real
one.
