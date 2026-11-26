---
status: approved
issue: 1942
spec: spec/2026-11-26-1942-schedule-watchdog.md
coders:
  1: coder # the fixture check: many cases, plain shell in a Nix string
  2: codex # small, tricky date and decision logic
  3: coder # one list entry
  4: coder # prose in two registers
reviewers:
  - codex # the decision logic against the spec's seven steps
  - agy # the check's cases against the spec's list, looking for one that cannot fail
---

# Plan: a missed scheduled workflow is started by a watchdog

Approved decisions, carried from the spec:

- `.github/scripts/schedule-watchdog.sh` holds a table of the ten scheduled
  jobs (workflow, cron in UTC, dispatch input, extra counting event, rows it
  waits for), exactly as in the spec's table.
- Slot `T` is the latest UTC cron fire at or before `NOW`; only `M H * * *` and
  `M H * * D` are understood, anything else exits non-zero; a slot older than
  24 h is never acted on.
- A qualifying run is on `main`, created at or after `T`, from `schedule` or
  `workflow_dispatch` (plus `push` for `build.yml`), not concluded `cancelled`;
  for `weekly.yml` the named job ran (its job list shows it not skipped).
- Decision per row, in table order: (1) under 45 min after `T`: not due;
  (2) a qualifying run: done; (3) any run on `main` not `completed`: leave;
  (4) a row it waits for has no qualifying run for its own slot, or one still
  running: leave; (5) `nightly` while `vm-host-free.sh install` or `edge` does
  not print `free`: leave; (6) a marker for workflow+input+`T` under
  `$STATE/schedule-watchdog/`: leave; (7) re-read runs, dispatch on `main` with
  the input if (3) still holds, write the marker, print it.
- One run listing per workflow per tick, `branch=main&per_page=50`, no
  `status=` filter; job lists only for `weekly` runs in a live slot.
- A failed read skips that workflow's rows and makes the exit non-zero after
  the rest. `TZ=UTC`, arithmetic on epoch seconds only. `GH_REPO` set by the
  script. `NOW`, `GH`, `STATE` overridable; `--dry-run` prints decisions.
- One notification after all rows, failure ignored.
- The p620 timer (every 5 min, fine-grained token from agenix as `GH_TOKEN`)
  is a separate pull request in `nixos_config`, after this one merges; it is
  not part of this plan.

## Steps

1. `tests/schedule-watchdog.nix` (new): a `runCommand` with a stub `gh` that
   answers `api` calls from fixture JSON per workflow (and can fail one
   workflow's read), records `workflow run` calls to a file, and a stub
   `vm-host-free.sh` via a `VM_HOST_FREE` override. One case per bullet in the
   spec's check list, each a fixed `NOW` and fixtures, asserting the recorded
   dispatches exactly. Plus the table comparison against `.github/workflows/`:
   every `- cron:` line has a row and back, each row's workflow has
   `workflow_dispatch:`, each `weekly` input is in `job`'s `options`, each
   `weekly` job's `if:` names its cron and its input; each failure names the
   row. → `nix build .#checks.x86_64-linux.schedule-watchdog` fails, because
   the script does not exist yet (the red half of §1).
   Traps: `''` string, so no heredoc; write fixtures with `printf` (§5). `git
   add` the new file before building (§5). Not `! cmd` for a negative
   assertion: `set -e` ignores it; use `if cmd; then exit 1; fi`. Run the
   time cases also under `TZ=America/New_York`.
2. `.github/scripts/schedule-watchdog.sh` (new, `#!/usr/bin/env bash`, `set
   -euo pipefail`): the table and the seven steps above. Capture command
   output with `out=$(cmd) || ...`, never `mapfile < <(cmd)` (§4); `set -e`
   does not reach into `$(...)` (§5). `10#` is not needed if no `%H`/`%M`
   arithmetic is done; do none. → the same check passes.
3. `flake.nix`, the checks name list beside `"pin-fix"`: add
   `"schedule-watchdog"` with a one-line comment. → `nix eval
   .#checks.x86_64-linux.schedule-watchdog.drvPath` succeeds, and
   `.github/scripts/generated-checks.sh generated` lists it (§4: no workflow
   edit).
4. `docs/internals/workflows.md`, a section after `review.yml`'s: what the
   watchdog does, where it runs, the residual races, and that it reads the
   table at p620's pin. `tests/AGENTS.md`: a row for the check. → `nix build`
   of the docs checks the generated set includes passes.

5. (Deviation, found by the live dry run on 2026-11-26.) The script cancels
   GitHub's late `schedule` run of a daily slot the watchdog dispatched (marker
   present, run on `main`, not completed, created at or after `T`); never a
   `weekly` run, a run started by hand, or a slot without a marker. The check
   gains a stubbed `api -X POST .../runs/<id>/cancel`, every case asserts the
   cancels it expects (none by default), and seven cases cover the rule. The
   timer ticks every 5 minutes rather than 15, so a late `nightly` is
   cancelled before it gets far.
6. (Deviation, found by the same dry run.) The script's API replies were held
   in a variable named `out`, which a dev shell exports; bash keeps the export
   on a `local`, so a 250 KB reply reached every child's environment and `jq`
   failed with E2BIG. Renamed, and a case with a reply over 128 KiB fails with
   the old name.

## Tests

- §1: after step 2 passes, break each decision once (drop step 3's status
  test; drop the weekly job-ran test; drop the 24 h bound; drop a table row)
  and show the check fails naming the case; restore with `git checkout HEAD
  --`. Save the red output for the PR.
- Every target `generated-checks.sh generated` prints; `checks.grep-q-pipefail`;
  `nix fmt -- --ci`; statix and deadnix.
- `bash .github/scripts/schedule-watchdog.sh --dry-run` against the live API
  prints a decision for every row and dispatches nothing.

## Rollback

Revert the commits. Nothing runs the script until the `nixos_config` timer
lands.
