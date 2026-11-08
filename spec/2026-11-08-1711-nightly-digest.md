---
status: draft
issue: 1711
intent: intent/2026-11-08-1711-nightly-digest.md
---

# Spec: a nightly failure report says why, without its run

## Design

### Measured first

A build killed partway keeps a readable, truncated log in p620's store. Two
install builds from 2026-10-24 under `/nix/var/log/nix/drvs` end mid-boot
(`BTRFS info …`) with no test-driver footer. So `nix log <drv>` holds what a
timed-out check printed up to the moment it died, which is the excerpt a
reader wants.

### 1. A `digest` job (`.github/workflows/nightly.yml`)

A new job, placed before `report`:

- `runs-on: [self-hosted, nixos, kvm, big]`, the install jobs' labels, so it
  runs where p620's store is. It runs no VM and no build; it evaluates
  derivation paths and reads logs.
- `needs:` the same list as `report`, and the same condition, copied
  verbatim with a pointer to `report`'s comment, which carries why it is
  shaped that way (#903, 2026-09-23): `always() && (contains(join(needs.*.result, ','), 'failure') || contains(join(needs.*.result, ','), 'cancelled'))`.
- `permissions: { contents: read, actions: read }`, the second to list the
  run's jobs.
- Steps: checkout at `github.sha`, then `.github/scripts/nightly-digest.sh`
  run under `nix shell --inputs-from . nixpkgs#gh nixpkgs#jq nixpkgs#yq-go -c`:
  a self-hosted step has only what its environment provides (§4,
  `curl: command not found`), and the script needs Go `yq` syntax,
  which writes its text to a job output `text` under a random heredoc
  delimiter. The step has `continue-on-error: true` and the script always
  exits 0.

### 2. `.github/scripts/nightly-digest.sh` (new)

For the current run (`GITHUB_RUN_ID`, `GITHUB_REPOSITORY`):

1. `gh api --paginate repos/$REPO/actions/runs/$RUN/jobs`, captured then
   split (§4, `mapfile < <(…)` hides a failure). For each job whose
   conclusion is `failure`, `cancelled` or `timed_out`, it reads the job's
   name, its conclusion, and the first step whose conclusion is not
   `success` or `skipped`.
2. Each job's checks come from `nightly.yml` itself:
   `yq '.jobs.<id>.steps[].run'`, every `checks.x86_64-linux.<name>` named
   there. The job id is found by matching the API's job name against
   `.jobs.<id>.name // <id>`. Nothing hand-kept (§4, a hand-maintained list
   fails open).
3. For each check: `nix eval --raw .#checks.x86_64-linux.<name>.drvPath`,
   then `nix log <drv>` piped through `failure-excerpt.sh` and `tail -n 40`,
   the same treatment `failure-digest.sh:70` gives a root failure. No log
   yields "no build log (it never started, or it was substituted)".
4. Output, per failed job:
   ```
   ### <job name>: <failed|timed out or cancelled> at step "<step>"
   <check>: <excerpt in a fenced block>
   ```
   A job with no checks (`cache`, `canary`, `pkg-new`, `commit-independent`)
   gets the header line only.
5. The whole text is capped at 50,000 characters, cut at a line boundary and
   marked "(digest truncated)", which leaves room for the issue's own text
   under GitHub's 65,536.

Any failure inside (the API, `yq`, an evaluation) is caught. The script
prints `digest unavailable: <what failed>` and exits 0, so `report` still
reports.

### 3. `report` uses it (`.github/workflows/nightly.yml`)

- `needs:` gains `digest`. Its condition is unchanged: a skipped or failed
  `digest` cannot stop it, because the condition reads the other jobs'
  results with `always()`.
- The digest reaches the shell through `env: DIGEST: ${{ needs.digest.outputs.text }}`,
  never interpolated into the script text: it holds build output, and
  `${{ }}` in a `run:` block is a script injection.
- The opening body and the "still failing" comment both append
  `$DIGEST`; if it is empty, they append
  `Digest unavailable (digest job: ${{ needs.digest.result }}).`

## Alternatives rejected

- **A digest step inside each failing job.** A job that hits
  `timeout-minutes` is cancelled, and #1604's case was a timeout.
- **`report` digests `gh api` job logs.** The parser anchors at line start
  (`failure-digest.sh:27`) and job logs carry a timestamp prefix; a hosted
  runner has no `nix log`; and the job log holds only the last lines nix
  streamed, not the check's own log.
- **Upload each build log as an artifact.** It needs a step that a timeout
  skips, and artifacts expire with the run, which is the problem.
- **Widen `failure-digest.sh`.** Its output for `build.yml` and edge must not
  change (intent constraint), and its input, a `--keep-going` build log, is
  not what the nightly has.

## Risks

- **The digest job takes a self-hosted slot** after a failed night. It runs
  no VM, and it is short: an evaluation per failed check and a log read. It
  runs only when something already failed.
- **Evaluation memory.** An install check's `drvPath` evaluates a VM
  closure, a few GB, once per failed check. That is under the cheap tier's
  cost and happens after the VMs have stopped.
- **A different `drvPath`** than the one built, if the checkout differed.
  Both use `github.sha`, and checks build from a committed tree (§5), so they
  match. A mismatch reads as "no build log", not as a wrong excerpt.
- **Public text.** The excerpt is build output, as edge's issues already
  carry, filtered by `failure-excerpt.sh`. Nothing reads the environment.
- **§11.** Adding a job to a workflow is a CI change a human merges. No
  trigger, required check or timeout moves, and `report`'s condition is
  untouched.

## Verification

- **`checks.nightly-digest`** (new, `runCommand`, cheap): runs
  `nightly-digest.sh` against the real `nightly.yml` with stubs for `gh`
  (a fixture job list) and `nix` (`eval` prints a fake drv, `log` prints a
  fixture). Cases:
  1. `install` failed at its build step, with a log ending in a Python
     traceback → header names the job, the step and `install`, and the
     excerpt holds the traceback;
  2. `install-iso-net` timed out, with a truncated log → "timed out or
     cancelled" and the log's last lines;
  3. `install-iso-net` failed at the ISO size step → job and step, and both
     of its checks (`iso-budget`, `install-iso-net`);
  4. `canary` failed → header only;
  5. `nix log` prints nothing → "no build log";
  6. `gh` fails → `digest unavailable: …`, exit 0;
  7. a log larger than the cap → under 50,000 characters, ends with
     "(digest truncated)".
- **`actionlint`**: `build.yml`'s existing step (`:171-183`) lints every
  workflow on pull requests; run the same command locally.
- **§1 breaks**, each shown failing: drop the step lookup (case 1); map checks
  from a hard-coded name instead of `yq` (case 3's second check); drop the
  cap (case 7); remove the `|| …` guard on the API call (case 6).
- **Not testable locally:** the job's real run. The first failed night after
  merge is its proof, and the next "still failing" comment must carry a
  digest. Said in the PR.
