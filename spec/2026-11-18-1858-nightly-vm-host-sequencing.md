---
status: approved
issue: 1858
intent: intent/2026-11-18-1858-nightly-vm-host-sequencing.md
---

# Spec: measure the nightly's VM-host load before ordering anything

The intent is approved and left its open questions to this spec. The
evidence for harm is one hang that nightly overlap does not explain, so this
issue measures and corrects a stale comment. It changes no `needs:` and not
`vm-host-free.sh`.

## Design

### 1. `.github/scripts/vm-host-sample.sh <interval> -- <command...>`

A wrapper, not a daemon. It runs `<command>` in the foreground and returns
its exit status unchanged, and samples beside it in a background subshell.

Why a wrapper: a background process started in one step cannot be assumed to
survive into the next, or to be reaped at job end. Wrapping the existing
`nix build` step needs no cross-step state. This is the shape of the canary
sampler (`nightly.yml:506-515`: `( while :; do ...; sleep 20; done ) &`,
`trap 'kill "$sampler"' EXIT`), reused rather than reinvented.

Each sample is one greppable line, to stdout and appended to
`$GITHUB_STEP_SUMMARY` (defaulting to nothing when unset):

    vm-host: t=<s since start> load=<1m 5m 15m> mem_avail=<M>M qemu=<n> job=<GITHUB_JOB>

- `load` from `/proc/loadavg` (the §6 tier gate is "1-minute load below 12").
- `mem_avail` from `/proc/meminfo` `MemAvailable`.
- `qemu` is the count of `qemu-system*` processes on the host. This is the
  one signal that sees VMs from **any** workflow or from the owner's desktop,
  which is exactly what the intent could not establish for 11-18 03:19-03:25.
  It is a count of processes, not a claim about what they are doing.
- A first sample is written synchronously before the command starts and a
  last one after it ends, so a job shorter than the interval still leaves
  data. The `qemu` total is context only; it is not used to infer foreign VMs
  (see Decision 1).

Never fails the job: every sampling command ends `|| true`, the sampler's
stderr goes to `/dev/null`, and the wrapper's last act is `exit "$rc"` of
the wrapped command. The sampler is stopped by an EXIT trap.

The canary's known flaw (a killed loop orphans its `sleep`, the reason for the
`>/dev/null 2>&1` at line 511) is avoided rather than copied: the sleep is
`sleep "$i" & wait $!` inside a subshell that traps TERM, kills that sleep
and exits. No orphan, no redirect trick.

Shortcut: the busy-runner count from the intent's sketch is dropped.
`GET /repos/.../actions/runners` needs admin scope and the job's
`GITHUB_TOKEN` has none; `vm-host-free.sh` gets by on `actions/runs`. The
`qemu` count answers the same question from the host's side with no token.
Upgrade only if the data shows qemu processes with no nightly job to explain
them and the maintainer wants to know whose.

### 2. Wrapped steps in `nightly.yml`

The four VM-class `nix build` steps become
`.github/scripts/vm-host-sample.sh 30 -- nix build ... --print-build-logs`:
`install` (`nightly.yml:58`), `install-encrypted` (105),
`keyboard-boot` (122) and `microvm` (138). `install-iso-net` is
included too (its check build is line 194; the chain's second link) so every
VM-class job in a night has a row; its step is edited the same way. `repush`, `digest` and the hosted
jobs are untouched. Interval 30 s: a `Watchdog read timed out` freeze at guest
time 333 s (#1855) spans many samples, and a 90-minute job writes at most
~180 lines.

This is a workflow edit and therefore a CI-gate change a human merges
(CLAUDE.md §11). The PR says so.

### 3. Corrected comment

`nightly.yml:87-90` ("Same runner pool; the runner serialises the two jobs,
which is the point") is replaced with what is true: four p620 runners share
the labels, `install` and `install-encrypted` start in the same second on
different runners, and nothing serialises them except `install-iso-net`'s
`needs: [install]` (161). The header comment (lines 40-41, "One at a time"
above the `concurrency` block at 42-44) gets one sentence saying the group
serialises nightly *runs*, not jobs within a run. The adjacent
`install-iso-net` comment (143-148, "at most TWO install-class jobs ... through
two chains") is corrected in the same edit: it is the model the intent calls
unproven, so it is stated as the intended cap, not as what runs (all five
jobs without a `needs` start together, and `keyboard-boot` and `microvm` are
in no chain).

### 4. Where the data lands, and what reads it

Job summaries and logs persist with the run. `nightly-digest.sh` reads local
Nix derivation logs (`nightly-digest.sh:60`), not Actions job logs, so it
never sees the `vm-host:` lines; they are read by hand from the Actions log
(see Analysis). No change to
`nightly-digest.sh`, to avoid growing the issue body that #1856 was fitting
under a cap.

### Check

`tests/vm-host-sample.nix`, a `runCommand` in the shape of
`tests/commit-independent-shallow.nix`, registered in `flake.nix` beside
`commit-independent-shallow` (2519-2522). `generated-checks.sh` derives its
target list from the flake (`generated-checks.sh:102-103`, filtered at
123-127), and the check is not on `claimed`, so it is built on pull requests with no workflow edit (§4).
Cases, with a stubbed `/proc` via `VM_HOST_PROC` (the script reads
`${VM_HOST_PROC:-/proc}`) and a stub `pgrep` on `PATH`:

1. wrapped command exits 0: wrapper exits 0, summary file holds >= 2
   `vm-host:` lines (first and last) matching the field format.
2. wrapped command exits 7: wrapper exits 7 (the status is not swallowed).
3. `/proc/loadavg` missing and `pgrep` failing: wrapper still exits with the
   command's status and still writes a line (fields `?`) rather than dying.
   The first sample runs synchronously, so a failing read kills the wrapper
   before the command if unguarded.
4. `GITHUB_STEP_SUMMARY` unset: no error.
5. no orphan: a `sleep` shim first on `PATH` records its own PID to a file and
   execs the real `sleep`; the command runs longer than one interval. After
   the wrapper returns, `kill -0 <recorded pid>` must fail. A real process
   check, not the stubbed `pgrep`; parentage is not tested (an orphan is
   reparented away from the test shell).
6. final sample: interval 1000 s, command `true`: exactly 2 lines (first and
   last), so periodic samples cannot satisfy the count.

## Decisions for approval

1. **Measure first.** This issue ships (a) the passive sampler and (b) the
   corrected comment. No `needs:` and no `vm-host-free.sh` change. Sound
   against the repo: the only existing evidence of harm is #1855, which the
   intent shows nightly overlap does not explain (03:22-03:25 had no other
   nightly VM job), and the same watchdog line appears in passing nights.
   The decision is then made on data after **10 usable scheduled
   nightlies** (about a week and a half; 8 nights were already inspected by
   hand, so 10 new ones is a fresh, comparable sample). A night is *usable*
   only if at least one VM job has >= 3 `vm-host:` lines **and** its log shows
   the VM actually ran (guest output present, not a cache hit); other nights
   are listed but not counted. A change is
   proposed when either holds, otherwise the header says "measured, no
   sequencing needed" and §6 is left as is:
   - any night with 1-minute `load` above 12 (the §6 package-tier gate)
     during a window where two or more nightly VM jobs ran, **and** a
     guest-side starvation signature in the same window (`udevd` worker
     kills, `dhcpcd` timeouts, or userspace boot over 60 s, per #1365's
     signature, not the watchdog line alone); or
   - a `vm-host:` window overlaps a self-hosted job from another workflow
     (install-check, omarchy-edge `verify`, found from `gh run list` job
     intervals on the same runner pool) while a nightly VM job ran. The
     `qemu` total is shown beside it as context only; a `qemu` process with
     no workflow job to explain it is recorded as *unattributed*, not as a
     foreign VM (jobs do not map one-to-one to qemu processes:
     `tests/keyboard-boot.nix:71` defines two guests).
   Both rules are cheap to revisit: they only choose when to look.

   **Analysis (manual, no analyzer):** per usable night and VM job, take the
   `vm-host:` lines of the job's Actions log and, from the same log, the
   guest `Startup finished ... (userspace)` time and any `udevd` worker
   kill or `dhcpcd` timeout. Separate build time from VM time by the log's
   own timestamps. Tabulate in the issue comment. Actions logs prefix every
   line with a UTC timestamp, so strip it first.
2. **Decision stays in #1858's scope.** The PR uses `Refs #1858`, not
   `Closes`: the intent's outcome 2 (sequencing, or evidence none is needed,
   stated in the workflow) is not met until the assessment below is done.
   After 10 usable nights the maintainer-approved assessment is recorded in
   an issue comment, and the follow-up edit (header "measured, no sequencing
   needed", or `needs:` changes) lands under #1858, which closes then. Intent
   open questions 1 (is a nightly wait acceptable) and 3 (how many nightly VM
   jobs at once; whether exclusion spans workflows) are answered at that
   point. Narrowing the intent instead would need its approval; not
   proposed. Which mechanism follows from those answers:
   `needs:` for nightly peers (never a concurrency group, `nightly.yml:152-155`),
   and a new `vm-host-free.sh` participant only if foreign VMs show up in the
   `qemu` column. Any such change keeps the exit-2 fail-closed behaviour.
3. **Wrapper, not a background step** (new, from verification): see Design 1.
4. **`qemu` count instead of busy-runner count** (new): see the shortcut note.

## Alternatives rejected

- **Sequence `keyboard-boot` after the others now.** Adds its runtime (up to
  23m38s, intent) to the nightly on one hang that overlap does not explain.
  Decide after the data.
- **A separate sampler job per night.** A job lands on one of four runners
  and starts when it likes; it samples a host, not the window of a given VM
  job, and costs a runner slot.
- **Systemd/node-exporter on p620.** The runner host config is in another
  repository and a deploy to p620 kills installs in flight (§6).
- **A background `&` in its own step.** No guarantee it outlives the step.
- **Posting samples to the issue digest.** Competes with #1856's size cap
  and the digest only runs on failure, so the passing nights (the control
  group) would be missing.

## Risks

- The sampler adds a handful of `/proc` reads and one `pgrep` every 30 s on a
  loaded host. Negligible, but nonzero; it is the measurement of a system by
  a process inside it.
- A wrapped step's log gains up to ~180 lines per job. `--print-build-logs`
  already emits far more.
- Changing `nix build ...` to a wrapper changes the step's process tree; a
  runner cancel kills the whole tree, and the EXIT trap may not run on
  SIGKILL, leaving at most one orphaned sample loop until job cleanup.
- Ten nights may not contain a hang, so the data can only confirm "no harm
  seen". The thresholds then say do nothing, which is a legitimate outcome.
- Could not verify here: that a self-hosted runner reaps stray children at
  job end (the reason for the TERM trap rather than relying on it), and
  `pgrep` availability on the runner's step PATH (§4: a step's shell carries
  only what the environment provides). The wrapper therefore reads `/proc`
  directly and falls back to `qemu=?` when `pgrep` is absent; case 3 covers
  it.

## Coexistence

None: this adds a CI script and a check and touches nothing a user's NixOS
configuration merges.

## Verification

Tiers per §6: `tests/vm-host-sample.nix` is a `runCommand`, cheap, run one at
a time under `flock /mnt/data/vmtest/codex-build.lock`. No VM, no package-tier
build, and no dispatch: sampling begins with the next scheduled nightly.
Run `nix fmt -- --ci`, `statix`, `deadnix`, `checks.grep-q-pipefail` (new
shell), and `actionlint` if available. Not run locally: the workflow itself
(needs a nightly on p620); the PR says so.

**§1 break proof** (write the break, prove it applied with `git diff`, build
the check, capture the failure, restore with `git checkout HEAD -- <path>` and
rebuild green; a new file is first committed as a baseline):

- Break A: change the wrapper's last line from `exit "$rc"` to `exit 0`.
  Case 2 must fail with `wrapper swallowed exit status`.
- Break B: delete the `|| true` after the `/proc/loadavg` read. Case 3 must
  fail (the synchronous first sample dies before the command runs).
- Break C: replace `sleep "$i" & wait $!` with a plain `sleep "$i"` and drop
  the TERM trap. Case 5 must fail because the recorded sleep PID is alive.
- Break D: remove the final sample. Case 6 must fail (1 line, not 2).

Also a **real first-night check**: after the next nightly,
`gh api repos/olafkfreund/nixarchy/actions/jobs/<id>/logs > log || echo FETCH-FAILED`
then `sed 's/^[^ ]* //' log | grep -c '^vm-host:'` is non-zero for each of
the five VM jobs, and each job's conclusion is as expected (status
preservation itself is proved by case 2, not by another night). Until that is seen, the sampler is untested in CI. The PR names
that as pending.

Cited and read in this worktree: `nightly.yml` 40-44, 47-161, 483-547,
609-641; `vm-host-free.sh` 1-30; `generated-checks.sh` 1-60;
`tests/commit-independent-shallow.nix` 1-40; `flake.nix` 2500-2530. Not
verified: runner PATH contents, `pgrep` on runners, p620 load on any past
night.
