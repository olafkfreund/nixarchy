---
status: draft
issue: 1853
spec: spec/2026-11-18-1853-omarchy-job-stall-no-diagnostics.md
coders:
  1: coder   # one-step YAML insert, mechanical
  2: codex   # small tricky logic: process-group kill, deadline arithmetic, exit-status passthrough
  3: coder   # swap one command for a wrapper call in a workflow
  4: codex   # tricky fixtures: flock waiter, socket activity, break-proof messages (codex cannot build; the session runs every check)
reviewers:
  - codex   # independent read-only review of script and test; output is advice only, never approval
---

# Plan: a stalled `omarchy` step 28 leaves its evidence and is bounded (#1853)

Every approved spec decision, so this plan stands alone.

## What is being built

The `omarchy` job in `.github/workflows/build.yml` stalled twice in three days
in step 28 ("Verify the generated menu defaults and app template",
`build.yml:1228`), each time ending only at the 60-minute job cap
(`build.yml:308`), reported `cancelled`, with no evidence of what nix waited on.

Approved decisions (owner, 2026-11-18):

1. Diagnostics are required, not only a shorter stall.
2. Scope: a **bound for step 28 only**. A stall in any other step is still
   cancelled at the cap, with no evidence. This narrows the intent's outcome
   and was accepted.
3. Step 28 deadline: `min(1500 s, remaining job budget - 5 min reserve)`.
4. No automatic re-run. The stall stays red with its evidence (section 10).
5. (Posting to #1853) **not adopted**, see 6.
6. **Resolved at approval: the SMALLER size.** `run` mode only. No `watch`
   mode, no background step, no `cancel` step, no `gh issue comment`, no
   `issues: write` permission change. Evidence goes to the log,
   `$GITHUB_STEP_SUMMARY` and a `::error` annotation; the owner copies the
   summary into #1853 by hand. Gives up: evidence for a stall outside step 28,
   and evidence that outlives a deleted run.

Behaviour of `.github/scripts/stall-watch.sh run <seconds> <log> -- <cmd...>`:

- Runs `cmd` in its own process group (`setsid`), output teed to `<log>` and to
  the runner log; exits with `cmd`'s own status (pipefail on, so `tee` cannot
  hide it, CLAUDE.md section 1).
- Effective deadline = `min(<seconds>, 3600 - (now - JOB_T0) - 300)`, exactly
  as the approved spec (`spec:20-24`) says: no floor. A value at or below zero
  means the command is started and the deadline path runs on the first poll
  (snapshot, kill, 124); the poll loop tests the deadline before sleeping. If `JOB_T0` is unset the plain `<seconds>` is used and the snapshot
  header says `JOB_T0 unset`. Runner setup before the first step is not counted;
  the 5-minute reserve absorbs it.
- At the deadline, in this order: (1) snapshot, (2) write it to
  `$GITHUB_STEP_SUMMARY` and emit `::error title=omarchy-stall::...`, (3) kill
  the group (TERM, KILL after 10 s), (4) exit 124. Evidence first, kill second.
  Reporting is best effort: every write in (1)-(2) ends `|| true` (a full disk
  or unwritable summary must not skip the kill), and every kill/wait in (3)
  tolerates a group that already exited (`|| true`). Cleanup and exit 124 always
  happen.
- Snapshot, inside `::group::omarchy-stall`, each section `timeout 10 ... || true`
  and labelled, so a missing tool is a missing section, never a hang:
  `== process forest ==` (`ps -eo pid,ppid,etime,stat,wchan:20,args --forest`),
  `== /proc/locks ==` (a `->` line is a blocked waiter with its pid),
  `== sockets ==` (`ss -tnpi`: `bytes_received`, `lastrcv`, `lastsnd`),
  `== nix fds ==` (`ls -l /proc/<pid>/fd` for each `nix`/`nix-daemon` pid),
  `== disk/mem ==` (`df -h /nix`, `free -m`), `== nix-daemon journal ==` tail,
  `== recent builder logs ==` (mtime-sorted tail of `/nix/var/log/nix/drvs`),
  `== log tail ==` (last 30 lines of `<log>`).
  It prints raw inputs, not a verdict. Reading rule (documented in the script
  header, not coded): lock = blocked `/proc/locks` waiter in the nix tree;
  download = nix-owned socket with recent `lastrcv`/non-zero `bytes_received`
  and no builder; build = builder child with a growing log; else unclassified.
- Because step 28 now fails (not `cancelled`), `if: failure()` steps run, so
  `Failure digest` (`build.yml:1296`) runs on a stall for the first time. It
  reads `build-unless-proven.sh`'s log, so it will say little; harmless, and it
  always exits 0.
- Step 28's Python heredoc and `nix-instantiate` (`build.yml:1233-1291`) stay
  unchanged; only the bare `nix build` is wrapped. `nix-instantiate` stays
  unbounded (accepted, decision 2).

Risks carried (state in the PR): false cancel on a cold store past 25 min
(visible as `omarchy-stall`); `ss`/`journalctl` may be absent or need root on
the hosted runner (partial snapshot, never a hang); does not explain the 11-16
stall's cause. The `build.yml` edits are CI-gate changes (section 11): **the PR
proposes them and a human merges.**

## Steps

Do not implement before this plan is `status: approved`. Name the step being
executed in each commit.

### Step 1 - record job start (coder)

`.github/workflows/build.yml`, insert a new first step directly before the
"The gate did not succeed" step (`build.yml:310`, first entry of `steps:` after
line 309):

```yaml
      - name: Record when the job started
        run: echo "JOB_T0=$(date +%s)" >> "$GITHUB_ENV"
```

No `if:`, so it always runs and is the earliest point available without
touching the other steps. Smallest way to give step 28 a job clock; no
background step.
→ verify: `grep -n 'JOB_T0' .github/workflows/build.yml` shows the write at
the top of `steps:`; `nix shell --inputs-from . nixpkgs#actionlint -c actionlint -ignore
'SC[0-9]+:(info|style):' .github/workflows/build.yml` clean (the exact command
of `build.yml:177-184`, which carries the ignore because existing info/style
notes fail without it, restricted to the one file).
Traps: section 11 (CI-gate change: propose, human merges); one `$(...)` in a
`run:` is fine, no `''` string involved.

### Step 2 - the script (codex)

New file `.github/scripts/stall-watch.sh`, executable (`chmod +x`, and
`git add` it: section 5 flake sees tracked files only). `#!/usr/bin/env bash`,
`set -Eeuo pipefail`. Only `run` mode; any other first argument prints usage
and exits 2. Header comment states the reading rule and that the script never
changes a job's status except by the 124 at the deadline. Structure:

- `snapshot()` printing the sections above, each `timeout 10 <cmd> 2>&1 || true`
  (guard for `$log` unreadable). No python, no `-c '` (inline-python rule).
- `run_cmd()` launches `setsid bash -c 'set -o pipefail; "$@" 2>&1 | tee -- "$0"' "$log" "$@" &`
  and records `pid=$!`; the group id equals `pid` (setsid from a non-leader
  background job does not fork; if `setsid` is not available the script fails
  loudly, it is in `util-linux`).
- Poll loop `while kill -0 "$pid" 2>/dev/null; do ...; sleep 1; done` with a
  deadline test; on normal exit `wait "$pid"` and `exit` with its status
  (capture `rc=0; wait "$pid" || rc=$?`, section 5 `set -e` rule; never
  `$(...)` around it).
- On deadline: `snapshot | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}" || true`
  once (also to stdout; `|| true` so a failed summary write cannot abort under
  `set -e` before the kill), `echo "::error title=omarchy-stall::<cmd> exceeded <n>s ..."`,
  then `kill -TERM -- "-$pid" 2>/dev/null || true`, wait up to 10 s, `kill -KILL
  -- "-$pid" 2>/dev/null || true`, reap with `wait "$pid" 2>/dev/null || true`,
  `exit 124`. The `::error` text must not contain `== process forest ==`
  (so the test cannot be satisfied by the annotation, spec break 1).
- Do not use `pkill`, name-based kills, or `trap` with a local (sections 5, 6).

→ verify: `shellcheck .github/scripts/stall-watch.sh`; step 4's check.
Traps: section 1 (pipefail and `tee`: status is the left side's, proven by
break 3); section 5 (committed tree before any build that reaches it; run
`nix fmt` and read `git diff --stat` after any `.nix` edit; no `''` string in
this file); section 6 (no `pgrep`/`pkill` by name); section 4 (do not add a
`mapfile < <(...)`).

### Step 3 - wire step 28 (coder)

`.github/workflows/build.yml:1231-1232`: replace

```
nix build .#nixosConfigurations.vm.config.system.build.toplevel \
  --print-build-logs -o result-sys
```

with

```
.github/scripts/stall-watch.sh run 1500 "$RUNNER_TEMP/step28.log" -- \
  nix build .#nixosConfigurations.vm.config.system.build.toplevel \
  --print-build-logs -o result-sys
```

Leave lines 1233-1291 (comment, Python heredoc, `nix-instantiate` at 1291) byte-identical.
→ verify: `git diff -U0 .github/workflows/build.yml` shows only the step-1 insert
and these lines; `.github/scripts/stall-watch.sh` is referenced by exactly one
workflow line.
Traps: section 11 (human merges); step 28's Python heredoc is column-sensitive,
do not reindent it.

### Step 4 - the check (codex)

New `tests/stall-watch.nix`, a `runCommand` (`nixarchy-stall-watch`), no VM,
`nativeBuildInputs`: bash, coreutils, procps, util-linux (setsid, flock),
iproute2 (ss), gnugrep, gawk, findutils, python3 (case G listener only). Copy the script like
`tests/failure-digest.nix:21-28` (`cp ${../.github/scripts/stall-watch.sh}`,
`patchShebangs`). Register in `flake.nix` beside `failure-digest` (after the
`failure-digest = import ./tests/failure-digest.nix {...};` block at
`flake.nix:2501-2504`, with a `# #1853:` comment). Use `printf '%s\n'`, never a
heredoc (section 5). Fixtures stay inline; `fail()` messages exactly as below
because the break proofs name them. Cases (deadline small via `<seconds>`;
`GITHUB_STEP_SUMMARY` pointed at a temp file; bash scripts under bash):

- A: `run 2 log -- sleep 600`: exit 124; stdout contains `== process forest ==`
  and `sleep 600`; the summary file contains `== process forest ==`; the sleep
  pid is gone (`kill -0` fails). Messages: `A: no '== process forest ==' in
  output`, `A: exit <n>, wanted 124`, `A: sleep 600 still running`.
- B: `run 30 log -- true`: exit 0, no `== process forest ==`.
- C: `run 30 log -- sh -c 'exit 3'`: exit 3, no snapshot. Message
  `C: exit <n>, wanted 3`.
- D: `ss` absent (PATH built without iproute2): exit 124, `== process forest ==`
  and `== disk/mem ==` still printed (not `/proc/locks`, which only F asserts,
  so break 7 reaches F first-hand).
- F: a helper holds `flock` on a file; the command is a second process blocked
  on it; the `== /proc/locks ==` section contains a line with `->` naming the
  second pid. If `/proc/locks` is unreadable in the sandbox, F
  fails with `F: /proc/locks unreadable` rather than skipping: a case that
  passes by skipping is section 1's green light (lead's review). Message
  `F: no '->' waiter line in /proc/locks section`.
- G: local listener (a `python3 -I` script file written with `printf '%s\n'`,
  not `-c`; bash `/dev/tcp` only connects, it cannot listen) with
  one client sending bytes and one idle; the `== sockets ==` section shows
  differing `lastrcv`/`bytes_received`. Message `G: sockets do not differ`.
- I: static wiring: `grep -q` is not used on a pipe; use `grep -qF` on the file:
  step 28 of `${../.github/workflows/build.yml}` calls `stall-watch.sh run`, and
  the job's first step writes `JOB_T0`. Messages
  `I: step 28 does not call stall-watch.sh`, `I: no JOB_T0 step`.
- J (extra, covers the budget cap, which is core to decision 3): `JOB_T0=$(( $(date +%s) - 3297 ))`,
  `run 600 log -- sleep 600` under an independent outer `timeout -k 5 60`: the
  wrapper must exit 124 within 20 s (`SECONDS` measured), header names the
  shortened deadline. The outer timeout's own 124 is told apart by elapsed time
  (>= 60 s means the outer fired) and by the absence of the wrapper's
  `omarchy-stall` annotation in the output. So a broken deadline fails in about
  a minute, never ten, never a hang. Message `J: deadline not capped by job budget`.

Dropped by decision 6: spec cases E (gh) and H (watch), breaks 5.
→ verify: see Tests. Also confirm registration:
`nix eval --raw .#checks.x86_64-linux.stall-watch.drvPath` (after `git add`),
and `.github/scripts/generated-checks.sh names | grep -x stall-watch` and
`.github/scripts/generated-checks.sh | grep stall-watch` (target list, i.e. not
in `claimed` or `exempt`: section 4, no workflow edit for the check itself).
Traps: section 1 (prove it fails); section 5 (nixfmt, `''` strings, committed
tree, `git add`); section 3 (F and G vary the variable that matters; sockets
case starts each field non-empty); `checks.inline-python` (no `python -c '` at
end of line in the new file); `checks.grep-q-pipefail` (no `| grep -q`; this
plan's own `grep` commands use files, not pipes); section 6 (cheap tier).

## Tests

Tree must be committed first (section 5; the break loop restores with
`git checkout HEAD -- <path>`, section 5). Cheap tier, one at a time:
`flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.<name> --print-build-logs`
(never piped; check the exit status). Evaluate once first
(`nix eval --raw .#checks.x86_64-linux.stall-watch.drvPath`, section 5).

Green path, after step 4:
- `stall-watch`, `grep-q-pipefail`, `inline-python`, `failure-digest` (unchanged
  neighbour): exit 0.
- Every target `.github/scripts/generated-checks.sh` prints, plus claimed checks
  whose files were touched (none expected).
- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`, `shellcheck` on the new script,
  the actionlint command from step 1 on `build.yml`;
  `OMARCHY_TREE=<built omarchy tree> .github/scripts/readme-counts.sh --check`
  (it exits 2 without `--check`/`--fix` and 1 without a tree with
  `share/omarchy/bin`, `readme-counts.sh:37-55`; a new check may move a derived
  count; if it refuses, teach it per section 4). The tree is a package-tier
  build, so run it only when that gate is free, else name it in the PR as not run.
- No VM, no package tier.

Break proofs (section 1). For each: apply the break, `git diff` proves it
landed, build, capture the red output, restore, build green.
1. Empty the `snapshot()` body. Expect `FAIL: A: no '== process forest ==' in output`.
2. Change the deadline branch's `exit 124` to `exit 0`. Expect `FAIL: A: exit 0, wanted 124`.
3. Replace the status capture so `rc` is taken from `tee` (`set +o pipefail`
   inside the `bash -c`). Expect `FAIL: C: exit 0, wanted 3`.
4. Remove the process-group kill. Expect `FAIL: A: sleep 600 still running`.
6. Remove the `stall-watch.sh run` call from step 28 in `build.yml`. Expect
   `FAIL: I: step 28 does not call stall-watch.sh`.
7. Drop the `== /proc/locks ==` section. Expect `FAIL: F: no '->' waiter line in /proc/locks section`.
8. (case J) Ignore `JOB_T0` in the deadline. Expect `FAIL: J: deadline not capped by job budget`.

Paste the failing output of 1-4, 6-8 in the PR (template section).

Not provable locally (name in the PR): that the hosted runner has `ss`,
`journalctl` access and `setsid`; that a real stall produces a useful
snapshot; the firing was seen in the test, not on a runner. A human may run a
throwaway `workflow_dispatch` with a `sleep` step to see it on a runner.
Also not verified here: whether `nightly.yml`/`omarchy-edge.yml` build the same
step (not touched).

## Rollback

Revert the commit: remove `.github/scripts/stall-watch.sh`,
`tests/stall-watch.nix`, its `flake.nix` entry, the step-1 insert and restore
the bare `nix build` at `build.yml:1231`. No state, secrets or permissions
change, so a revert is complete. If step 28 false-cancels healthy runs on cold
stores, raise `1500` in `build.yml` (a CI-gate change, human merge) rather than
removing the wrapper.
