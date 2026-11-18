---
status: approved
issue: 1858
spec: spec/2026-11-18-1858-nightly-vm-host-sequencing.md
coders:
  - step 1 (vm-host-sample.sh): codex, small tricky logic (trap, wait, status preservation, never-fail guards)
  - step 2 (tests/vm-host-sample.nix + flake.nix registration): codex, the six cases are the tricky part; the flake entry is one block
  - step 3 (nightly.yml five wrapped steps): coder, mechanical
  - step 4 (nightly.yml comments): coder, mechanical text replacement from the spec
reviewers: [codex]
---

# Plan: #1858, measure the nightly's VM-host load before ordering anything

Spec: `spec/2026-11-18-1858-nightly-vm-host-sequencing.md` (approved).
Intent: `intent/2026-11-18-1858-nightly-vm-host-sequencing.md` (approved).

Steps that edit files: 4 across 4 files (script, test, flake.nix, workflow), so the
model-split rule applies (three or more steps). Builds, break proofs, commits and
the PR stay with the session. agy is out of use (#2748); no entry names it.

## Approved decisions carried over (self-contained)

1. **Measure first.** Ship a passive sampler and a corrected comment. No `needs:`
   change, no `vm-host-free.sh` change. Evidence of harm is one hang (#1855) that
   nightly overlap does not explain, and the same watchdog line appears on
   passing nights.
2. **Wrapper, not a background step.** `vm-host-sample.sh <interval> -- <command...>`
   runs the command in the foreground, returns its exit status unchanged, and
   samples from a background subshell stopped by an EXIT trap. No cross-step state.
3. **Sample line** (stdout and appended to `$GITHUB_STEP_SUMMARY`, skipped when unset):
   `vm-host: t=<s since start> load=<1m 5m 15m> mem_avail=<M>M qemu=<n> job=<GITHUB_JOB>`.
   `load` from `/proc/loadavg`, `mem_avail` from `/proc/meminfo` MemAvailable, `qemu`
   = count of `qemu-system*` processes on the host. A first sample is written
   synchronously before the command, a last one after it. `qemu` is context only,
   never used to infer foreign VMs.
4. **Never fails the job.** The script runs without `-e`, so a failed read cannot abort it;
   each field read has an explicit fallback to `?` (`x=$(cat ... 2>/dev/null) || x=?`), the
   sampler's stderr goes to `/dev/null`, the last act is `exit "$rc"`. Unreadable field is `?`.
   `qemu` is the exception to the `||` form: `pgrep -c` prints `0` and exits 1 when nothing
   matches, which is a valid idle-host reading, so the count is taken from its stdout
   regardless of status and only an EMPTY output (pgrep absent or failed) becomes `?`.
   `/proc` is read directly, root overridable by `VM_HOST_PROC` (default `/proc`).
   *Deviation from spec wording:* the spec says a guard failure "aborts" the sample; under
   `set -uo pipefail` (no `-e`) it does not, it yields an empty field. The contract is the
   `?` fallback, and Break B tests that. The spec sentence needs a one-line correction by the
   owner; this plan does not edit the spec.
5. **No orphan sleep.** Inside the sampler subshell: `sleep "$i" & wait $!`, with a
   TERM trap that kills that sleep and exits. The canary's `>/dev/null 2>&1` trick
   (`nightly.yml:511`) is not copied.
6. **Interval 30 s**, five wrapped steps: `install`, `install-encrypted`,
   `keyboard-boot`, `microvm`, `install-iso-net`. `repush`, `digest` and hosted jobs
   untouched.
7. **Comments corrected** (not behaviour): `nightly.yml:87-90` ("the runner
   serialises the two jobs, which is the point") is false; four p620 runners share
   the labels, `install` and `install-encrypted` start in the same second, and only
   `install-iso-net`'s `needs: [install]` (161) serialises anything. Header
   comment (40-41) gains one sentence: the group serialises nightly runs, not jobs
   within a run. `143-148` ("at most TWO install-class jobs ... two chains") is
   restated as the intended cap, not what runs: four VM jobs (`install`,
   `install-encrypted`, `keyboard-boot`, `microvm`) have no `needs` and are eligible to
   start together (runner availability decides actual starts); the fifth,
   `install-iso-net`, waits for `install` (161); `keyboard-boot` and `microvm` are in no
   chain. *Deviation:* the spec says "five jobs"; `nightly.yml:161` shows four.
8. **Data stays in the Actions log.** No change to `nightly-digest.sh` (it reads
   local Nix derivation logs, `nightly-digest.sh:60`, and runs only on failure; #1856
   is fitting the issue body under a cap).
9. **Decision after 10 usable scheduled nightlies.** Usable = at least one VM job with
   3 or more `vm-host:` lines and a log showing the VM actually ran (guest output, not
   a cache hit). Propose a change only if either holds: (a) 1-minute load above 12
   while 2+ nightly VM jobs ran, plus a guest starvation signature in that window
   (`udevd` worker kills, `dhcpcd` timeouts, or userspace boot over 60 s; not the
   watchdog line alone); (b) a `vm-host:` window overlaps a self-hosted job from another
   workflow (install-check, omarchy-edge `verify`) while a nightly VM job ran. A
   `qemu` process with no job to explain it is recorded *unattributed*. Otherwise the
   header says "measured, no sequencing needed" and §6 stays as is. Manual analysis,
   tabulated in an issue comment; Actions log lines carry a UTC prefix, strip it first.
   Procedure (spec "Analysis"): per usable night and VM job take the `vm-host:` lines plus,
   from the same log, guest `Startup finished ... (userspace)` time and any `udevd` worker
   kill or `dhcpcd` timeout; separate build time from VM time with the log's own
   timestamps (a high load during `nix build` compilation is not VM load). Rule (b)
   overlap is established from `gh run list` job intervals **on the same runner pool**
   (the p620 self-hosted runners), not any workflow anywhere. The follow-up edit is made
   only after the **maintainer-approved assessment** is recorded in an issue comment
   (spec, decision 2); the agent's own tabulation is not that approval.
10. **PR says `Refs #1858`, never `Closes`.** The follow-up (header or `needs:`,
    `needs:` for nightly peers, never a concurrency group per `nightly.yml:152-155`;
    `vm-host-free.sh` participant only if foreign VMs show in `qemu`; keep exit-2
    fail-closed) lands under #1858, which closes then.
11. **Rejected, do not build:** sequencing `keyboard-boot` now; a sampler job;
    systemd/node-exporter on p620; a bare `&` step; posting samples into the digest;
    a busy-runner count (needs admin-scope API, `GITHUB_TOKEN` has none).

## Steps

### Step 1. `.github/scripts/vm-host-sample.sh` (new) - coder: codex

Edits: create file, mode 755, `#!/usr/bin/env bash`, `set -uo pipefail` (not `-e`;
sampling must never end the wrapper). Model on the canary sampler
(`.github/workflows/nightly.yml:506-515`) and the style of `vm-host-free.sh:1-12`.

- Parse `$1` as interval, require `--` as `$2`, remainder is the command; usage error
  exit 2 otherwise (this is a trust boundary of the script, not of the job).
- `proc=${VM_HOST_PROC:-/proc}`. `sample()` builds one line from `$proc/loadavg` (fields
  1-3), `$proc/meminfo` MemAvailable (kB to M), `pgrep -c qemu-system`
  (name match; take stdout whatever the exit status, empty stdout becomes `?`, see
  decision 4), the `/proc` reads each guarded `2>/dev/null || v=?`. Append to `${GITHUB_STEP_SUMMARY:-/dev/null}` and print to stdout.
- Call `sample` synchronously, start the loop `( trap 'kill "$s" 2>/dev/null; exit 0' TERM; while :; do sleep "$i" & s=$!; wait "$s"; sample; done ) 2>/dev/null &`, set an EXIT trap that kills the loop pid and `wait`s it, run `"$@"`, `rc=$?`, `sample` once more, `exit "$rc"`.
- The sampler subshell must write no stdout of its own except sample lines.

→ verify: `bash -n` and `shellcheck` if present (do not install); step 2's six cases.
Traps: §1 (the wrapper passing proves nothing until Breaks A-D fail it, see Tests);
§4 (a step's shell carries only what the environment provides: read `/proc` directly,
use only bash builtins plus `sleep`, `pgrep` optional, `date` not assumed: take `t=`
from `$SECONDS`); §5 (`set -e` does not reach `$(...)`; this script avoids `-e` on
purpose, and every `/proc` `$(...)` read ends `|| v=?` (one fallback form throughout,
the Break B target); EXIT trap reads `$sampler` at
exit, so it is a global, not a function local); §5 (new shell file: run
`checks.grep-q-pipefail`, never `cmd | grep -q` under pipefail).
Not verifiable here: `pgrep` or `sleep` on the runner's step PATH.

### Step 2. `tests/vm-host-sample.nix` (new) and `flake.nix` registration - coder: codex

Edits: create `tests/vm-host-sample.nix` as a `runCommand` in the shape of
`tests/commit-independent-shallow.nix:1-40` (`{ pkgs, ... }:`, `nativeBuildInputs` bash,
coreutils, gnugrep, procps; `fail() { echo "FAIL: $*" >&2; exit 1; }`; script path
interpolated as `${../.github/scripts/vm-host-sample.sh}`). Use `printf` to write stubs,
never a heredoc (§5, nixfmt reindent). Add beside `commit-independent-shallow`
(`flake.nix:2519-2522`):

    vm-host-sample = import ./tests/vm-host-sample.nix {
      pkgs = pkgsFor.${system};
    };

with a one-line `# #1858:` comment in the style of 2519-2520. No workflow edit: it is not
on `claimed`, so `generated-checks.sh` (`:102-103`, filter `:123-127`) builds it on PRs.

Stub scripts start `#!${pkgs.bash}/bin/bash`, not `#!/bin/bash` (`tests/AGENTS.md:2400`,
the sandbox has no `/bin/bash`).

Cases (spec Check 1-6, plus 7): (1) command exits 0, wrapper exits 0, summary has 2 or more lines
matching the field format; (2) command exits 7, wrapper exits 7, else
`FAIL: wrapper swallowed exit status`; (3) `VM_HOST_PROC` pointing at an empty dir and a
`pgrep` stub that prints nothing and exits 127: still the command's status, and the line
asserts exactly `load=? ` and `mem_avail=?M` and `qemu=?` (the `?` fallbacks, not merely "a line");
(7) `pgrep` stub that prints `0` and exits 1 (real no-match behaviour): line has `qemu=0`;
(4) `GITHUB_STEP_SUMMARY` unset, no error; (5) a `sleep` shim first on PATH records its pid
then execs the real `sleep`, command runs longer than one interval, afterwards
`kill -0 <pid>` must fail; (6) interval 1000, command `true`: exactly 2 `vm-host:` lines.

→ verify: `git add` both files first (§5: a flake sees only tracked files), then
`nix eval --raw .#checks.x86_64-linux.vm-host-sample.drvPath` once, visibly, before building.
Traps: §1 (Breaks A-D below, all four); §3 (case 3 and 4 vary the inputs that the
happy path holds constant: missing `/proc`, absent `pgrep`, unset summary; case 6
varies interval vs duration); §5 (stubbed `pgrep` and shim `sleep` must not pollute
the real PATH of the harness; use a `bin/` dir prepended only for the run);
§6 (cheap tier, one at a time under the lock).

### Step 3. `.github/workflows/nightly.yml` - wrap five steps - coder: coder

Edits (CI-gate change, a human merges; §11): replace each
`run: nix build .#checks.x86_64-linux.<c> --print-build-logs` with
`run: .github/scripts/vm-host-sample.sh 30 -- nix build .#checks.x86_64-linux.<c> --print-build-logs`
at `nightly.yml:58` (install), `:105` (install-encrypted), `:122` (keyboard-boot),
`:138` (microvm-boot) and `:194` (install-iso-net). Touch no other line; the script's
mode bit is what lets it run (checked in step 1, `git ls-files -s` shows 100755).

→ verify: exact counts, not "non-empty":
`test "$(grep -c 'vm-host-sample.sh 30 --' .github/workflows/nightly.yml)" = 5`; read the
five check names (`grep -o 'checks.x86_64-linux.[a-z-]*'` on those lines) and confirm they
are install, install-encrypted, keyboard-boot, the microvm check and install-iso-net;
`git diff --numstat` shows `5 5` for the file; `actionlint` if installed (do not install).
Traps: §4/§11 (workflow edit, name it in the PR as a CI-gate change; actionlint cannot
run the nightly); §4 (`continue-on-error` is not added: a sampler failure must not hide, and
it cannot fail the job by design, step 1); §6 (a deploy or dispatch is not part of this:
no dispatch, sampling begins at the next scheduled nightly); §8 (PR text must not quote
a skip-CI marker). Not verifiable here: the workflow itself.

### Step 4. `.github/workflows/nightly.yml` - comments only - coder: coder

Edits, text only, no key or value:
- `nightly.yml:87-90`: replace with the true statement: four p620 runners share these
  labels, `install` and `install-encrypted` start in the same second on different
  runners, and only `install-iso-net`'s `needs: [install]` (161) orders anything.
  Keep the 2026-09-03 sentence about two install VMs sharing one disk if it still reads as
  history rather than as a claim about this workflow.
- `nightly.yml:40-41`: add one sentence after "One at a time.": the group serialises
  nightly runs, not jobs within a run.
- `nightly.yml:143-148` ("One of two chains, so at most TWO install-class jobs share
  p620"): restate as the intended cap, not what runs; the four jobs without a `needs`
  (`install`, `install-encrypted`, `keyboard-boot`, `microvm`) are eligible to start
  together, `install-iso-net` waits for `install` (161), and `keyboard-boot` and `microvm`
  are in no chain; point to #1858.

→ verify: `git diff -U0 .github/workflows/nightly.yml | grep '^[+-]' | grep -v '^[+-][+-]'
| grep -v '^[+-] *#'` prints exactly 10 lines (five removed and five added step-3 `run:`
lines, no other non-comment line; count with `| wc -l`).
Traps: §7 (comments say why at the line they protect, no narration); §1 (the check
for "comments only" is the grep above, run it, do not assume).

## Tests

By §6 tier. Everything here is cheap: `runCommand`, static, evaluation-only, one at a
time under `flock /mnt/data/vmtest/codex-build.lock`. No VM, no package-tier build, no
dispatch. Run under bash, not zsh, and with `set -o pipefail` for any pipe
(§1).

1. Commit a baseline (subject temporary, §8) with steps 1-2 so the break loop has
   something to `git checkout HEAD --` out of (§5). Every break: apply, prove it landed
   with `git diff`, build, capture the failure, restore with
   `git checkout HEAD -- <path>`, rebuild green. Unstaged breaks must be `git add`ed
   before building (flake sees only tracked files); that is why restore uses
   `HEAD --`, not `--`.
2. Green: `nix build .#checks.x86_64-linux.vm-host-sample --print-build-logs`.
3. Break A: last line `exit "$rc"` to `exit 0`. Expected failure line:
   `FAIL: wrapper swallowed exit status` (case 2).
4. Break B: delete the `|| v=?` fallback on the `/proc/loadavg` read (the script has no
   `-e`, so nothing aborts; the field comes out empty). Expected: case 3 fails on its
   `load=?` assertion (`FAIL: case 3 ...`; copy the exact text into the PR). Prove it landed
   with `git diff`.
   For every break (A-D): `nix eval --raw .#checks.x86_64-linux.vm-host-sample.drvPath`,
   `nix derivation show` and grep for the break, then `nix build '<drv>^*'` (AGENTS.md:545),
   so a stale evaluation cannot stand in for the mutation.
5. Break C: `sleep "$i" & wait $!` replaced by plain `sleep "$i"`, TERM trap removed.
   Expected: case 5 fails because the recorded sleep pid is alive
   (`FAIL: orphaned sleep ...`; exact text copied into the PR).
6. Break D: delete the final `sample` call. Expected: case 6 fails with 1 line, not 2
   (`FAIL: expected 2 vm-host lines, got 1`).
   Exact `FAIL:` strings are fixed by step 2's text; the expected output above is the
   contract, and a break that stays green means stop and check for a no-op break
   (§1: prove the break landed).
7. Whole-tree cheap tier, one at a time under the lock: `nix fmt -- --ci`,
   `nix run nixpkgs#statix -- check .`, `nix run nixpkgs#deadnix -- --fail .`,
   `checks.grep-q-pipefail` (new shell), `actionlint` if available, and every target
   `.github/scripts/generated-checks.sh generated` prints that the changed files reach.
   After `nix fmt`, read `git diff --stat` (§5, a hook may have reformatted `.nix`).
8. `git diff --cached` equals what was staged and `git merge-base origin/main HEAD` is
   current main before the push (§5).
9. Not run locally, named in the PR: the workflow itself (needs a scheduled nightly on
   p620). **Real first-night check, pending after merge:**
   `gh api repos/olafkfreund/nixarchy/actions/jobs/<id>/logs > log || echo FETCH-FAILED`,
   then `sed 's/^[^ ]* //' log | grep -c '^vm-host:'` non-zero for each of the five VM
   jobs, and each job's conclusion as expected. Until seen, the sampler is untested
   in CI.

## Rollback

Single PR, revert it: removes `tests/vm-host-sample.nix`, the flake entry, the script
and the five `run:` edits, and restores the comments. No state, no migration, no
cache or allowlist entry. If the sampler misbehaves in CI before revert, the expected
effect is extra log lines (it cannot change a step's status by design). Known limit (spec
Risks): a SIGKILL of the step (runner cancel) can bypass the EXIT trap and leave one sample
loop alive until runner cleanup; it only appends to a step summary and sleeps. Open
risk after rollback: none beyond the stale comments returning.

## Not verified

Runner PATH contents, `pgrep` and `sleep` on a runner, whether a self-hosted runner reaps
stray children at job end, p620 load on any past night. The line numbers above were
checked against current main in this worktree (`nightly.yml` 40-44, 58, 87-90, 105, 122,
138, 143-148, 161, 194, 506-515; `flake.nix` 2519-2522; `vm-host-free.sh` 1-12).

## Deviation after review (Codex on #1861)

The sampler's TERM trap now waits for the `sleep` it kills before exiting, so
the wrapper never returns with that child still in the process table (a zombie
answers `kill -0`, which case 5 reads as an orphaned sleep). The race is not
deterministic, so no break proof makes it fail on demand.
