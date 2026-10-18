---
status: draft
issue: 1341
spec: spec/2026-10-18-1341-system-bump-timeout.md
---

# Plan: a nixpkgs bump finishes inside the system job's limit

## Approved decisions, carried over

1. **Split `system` into two parallel jobs, `system-build` and `system-vm`,**
   and keep a job named **`system`** that passes only when both halves did.
   Branch protection's required contexts
   (`lint, omarchy, system, devenv-presets, box, install`) do not change.
2. **`system-build`** keeps everything that is not a VM boot: the toplevels,
   `coexistence`, the allowlisted tools and box image, the three cachix pushes,
   the MicroVM and box templates, `options`, and the cache budget. Everything
   that publishes stays here.
3. **`system-vm`** takes the VM boots: `session`, `integration`, `coexist`,
   `install-teardown`, `installer-ui`, `try-nixarchy`, `dashboard-clock`,
   `installer-wizard` and `plugin`. It pushes nothing but proofs.
4. **The aggregator** runs under `if: ${{ !cancelled() }}` and fails unless
   `gate`, `system-build` and `system-vm` all concluded `success`. This is
   #1134's pattern, because a skipped required check passes the merge gate
   (#1144).
5. **Each half keeps `timeout-minutes: 45`** and a per-commit concurrency
   group like today's.
6. **Verification is measured.** A throwaway draft PR with a red half must
   read `BLOCKED`. #1341 closes on the next nightly bump finishing without a
   re-run, not on merge.
7. **A CI-gate change.** The PR proposes it and a maintainer merges it (§11).

## Who does what

Three files change, so the coder (Sonnet) does steps 1–2, one
`SendMessage` per step. The lead does 3–5, plus every commit and push.

## Steps

### 1. [coder] `.github/workflows/build.yml`

- **Rename** the job `system:` (`:1306`) to `system-build:`, and its
  concurrency group's `-system-` to `-system-build-` (`:1348`).
- **Add `system-vm:`** directly after it. Copy `system-build`'s header and
  setup verbatim: `needs: gate`, `if: ${{ !cancelled() }}`,
  `runs-on: ubuntu-latest`, `timeout-minutes: 45`, a concurrency group with
  `-system-vm-`, then the steps up to and including `Free disk space`. Those are:
  - "The gate did not succeed, so this check cannot pass";
  - "Nothing here can affect a build";
  - `checkout`, `setup-nix`, and the pull-only `cachix-action` with its
    comments.
- **Move** these steps, comments included, from `system-build` to
  `system-vm`, keeping their order:
  - "Drive a session and the app-selection loop" (`:1474-1484`);
  - the run from "Build onto a config that already exists" (`:1614`) through
    "Add third-party plugins from real repos" (`:1667-1675`). That run is
    `integration`, `coexist`, `install-teardown`, `installer-ui`,
    `try-nixarchy`, `dashboard-clock`, `installer-wizard` and `plugin`.

  "Check every option both ways" and "The cache allowlist fits its budget"
  stay in `system-build`.
- **Add the aggregator** after `system-vm`:
  ```yaml
  # The required context. Two halves since #1341, so a bump with no proofs fits
  # each 45-minute cap; this job passes only when both did. Never skipped: a
  # skipped required check passes the merge gate (#1144).
  system:
    needs: [gate, system-build, system-vm]
    if: ${{ !cancelled() }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Both halves of the system check passed
        run: |
          fail=0
          for r in "gate=${{ needs.gate.result }}" "system-build=${{ needs.system-build.result }}" "system-vm=${{ needs.system-vm.result }}"; do
            [ "${r#*=}" = success ] || { echo "::error::${r%%=*} concluded '${r#*=}'; refusing to report system as passed (#1341, #1134)"; fail=1; }
          done
          exit $fail
  ```
- **Comments:** the `timeout-minutes` comment (`:1310-1317`) gains one
  paragraph saying that a nixpkgs bump has no proofs, so the VM boots moved to
  `system-vm` to keep each half inside 45 (#1341, with the two measured
  totals). The concurrency comment's "This job takes ~19 minutes" stays true
  of each half.

Verify: `nix run nixpkgs#actionlint -- .github/workflows/build.yml` is clean.
`grep -c 'build-unless-proven.sh .#checks.x86_64-linux' .github/workflows/build.yml`
is unchanged from main. Every check named in the old `system` job appears
exactly once across the two halves.

Traps:
- YAML indentation: a step moved with the wrong indent becomes part of the
  previous step's `with:`. `actionlint` catches most of this; read the moved
  blocks' first lines.
- Nothing else `needs: system` (grepped), so the rename breaks no dependent.

### 2. [coder] Docs

- `docs/internals/workflows.md:103-107`: `system` is now two halves and an
  aggregator. Say what each half runs, and why (#1341).
- `CLAUDE.md:583`: "`cache-budget.sh` fails the `system` job" becomes the
  `system-build` job. Leave `:294`, which is history.

### 3. [lead] Throwaway PR: the aggregator blocks on a red half (§4)

From this branch, `git worktree add --detach`, commit an `exit 1` as a new
first step of `system-vm`, push to `test/1341-red-half`, and open a **draft**
PR. When its run ends, record:
- `gh pr view --json mergeStateStatus` reads `BLOCKED`;
- `system` reads `failure` with `system-vm concluded 'failure'`.

Repeat with the `exit 1` in `system-build`. Then close the PR and delete the
branch. Run it when the install queue is empty, and cancel its install run if
it starts (§13: a throwaway PR should not hold an install slot).

### 4. [lead] Timing on the real PR

The PR's own run gives both halves' durations. Record them in the PR body next
to the spec's estimates (~32 and ~29 on a bump; a normal PR, with proofs,
should be well under that).

### 5. [lead] PR

- Squash to one commit: `The system check runs in two parallel halves, so a
  nixpkgs bump fits the 45-minute limit (#1341)`. Check `git merge-base` and
  `git show --stat`.
- The PR body:
  - links intent, spec and plan, and says which steps the coder did;
  - includes step 3's merge states and step 4's timings;
  - says it changes a CI gate, for a maintainer to merge;
  - says `Refs #1341`: the issue closes after the next nightly bump finishes
    without a re-run.
- No `merge-when-green`: a human merges.

## Tests

| command | expect |
|---|---|
| actionlint on `build.yml` | clean |
| `build-unless-proven` count | unchanged from main |
| throwaway PR, red `system-vm` | `BLOCKED`, and `system` names `system-vm` |
| throwaway PR, red `system-build` | `BLOCKED`, and `system` names `system-build` |
| the PR's own run | `system-build`, `system-vm` and `system` green |
| next nightly bump | both halves finish, no re-run |

## Rollback

Revert the PR. `system` is one job again with the same name, so branch
protection needs nothing either way.
