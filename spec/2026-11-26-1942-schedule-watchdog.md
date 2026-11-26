---
status: draft
issue: 1942
intent: intent/2026-11-26-1942-schedule-watchdog.md
---

# Spec: a missed scheduled workflow is started by a watchdog

## Design

Two pieces, in two repositories, because the decision is this repository's to
test and the clock has to live on a machine that is not GitHub.

**`.github/scripts/schedule-watchdog.sh`** (this repo) makes one decision per
scheduled job and acts on it. It carries a table of every scheduled job:

| workflow | cron | dispatch input |
|---|---|---|
| nightly.yml | `0 3 * * *` | |
| omarchy.yml | `0 4 * * *` | |
| update.yml | `0 5 * * *` | |
| review.yml | `0 6 * * *` | |
| omarchy-edge.yml | `0 6 * * *` | |
| flake-update.yml | `0 7 * * *` | |
| build.yml | `0 6 * * 1` | |
| weekly.yml | `0 9 * * 0` | `job=stable-session` |
| weekly.yml | `0 15 * * 0` | `job=install-stock-iso` |
| weekly.yml | `0 6 * * 1` | `job=propose` |

For each row it computes `T`, the most recent time at or before now that the
cron fired. It understands `M H * * *` and `M H * * D` only, and exits
non-zero on any other shape, so a new kind of schedule is taught rather than
skipped. Then:

1. Now is less than 75 minutes after `T`: not due. GitHub's own delay here
   runs 1 to 16 minutes (2026-11-13 to 24), so 75 leaves room without costing
   a day.
2. A run of that workflow was created at or after `T`, by any event (a run
   started by hand counts): done.
3. A run of that workflow is queued or in progress: leave it. A dispatch would
   evict a pending run or, for `omarchy-edge`, cancel the running one (§8).
4. Otherwise dispatch it on `main` with its input, and say so on stdout.

A row's runs come from one call,
`actions/workflows/<file>/runs?created=>=<T>&per_page=20`, plus one for the
in-flight states, so a tick costs at most 20 requests. The script refuses to
dispatch when a listing fails: a double run is worse than a late one, and the
next tick asks again. `NOW` and `GH` can be overridden, for the check.

For `weekly.yml`, "a run created at or after `T`" is only that job's run
while the three crons fall on different days or hours, which they do. The check
below asserts it, so a fourth cron that overlaps fails there.

**`checks.schedule-watchdog`** runs the script against a stubbed `gh` and a
fixed `NOW`, and asserts:

- a daily job past the margin with no run is dispatched, with no input;
- within the margin, nothing is dispatched;
- a scheduled run, or a run started by hand, after `T` means no dispatch;
- a queued or running run means no dispatch;
- a missed `weekly` job is dispatched with its `job` input, and the other two
  `weekly` rows are left alone that day;
- a failed listing exits non-zero and dispatches nothing;
- every `- cron:` line in `.github/workflows/` has a row in the table, and no
  row is missing from the workflows. This is the comparison §4 asks of a
  hand-kept list, and it names the missing row.

**The timer** is in `nixos_config`, on p620: a user service and timer for the
owner, every 30 minutes, running the script from the `nixarchy` input's store
path with `gh` and `jq` on its path and the owner's `gh` login. On a dispatch
it sends a desktop notification. Each dispatch is also visible in the Actions
list as `workflow_dispatch`.

## Alternatives rejected

- **A GitHub workflow on an hourly cron as the watchdog.** It runs on the same
  scheduler, and on 2026-11-25 that scheduler fired nothing.
- **An external cron service calling the dispatch API.** It needs a token with
  `actions: write` held by a third party.
- **Chaining workflows with `workflow_run`.** It helps the second workflow
  when the first runs, not when the first was never started.
- **A self-hosted runner job.** A runner only takes jobs GitHub hands it, so
  it is as blind as the scheduler.
- **Reading the crons from the workflow files at run time instead of a table.**
  The `weekly` inputs live in `if:` expressions, which a grep would have to
  parse. A table plus a check that compares it with the files is simpler and
  fails by name.

## Risks

- **p620 off or asleep:** no watchdog. Documented, not covered; p620 also hosts
  every runner, so a p620 outage stops more than this.
- **A late `nightly` overlaps a daytime install.** The same overlap the 03:00
  run would have had with a late install, and the install jobs already wait
  for `vm-host-free.sh`.
- **The owner's `gh` login expires.** The listing fails, nothing is
  dispatched, and the unit fails, which `systemctl --user --failed` shows. The
  verify script on p620 lists failed user units.
- **API budget.** At most 20 requests per tick, 40 an hour, against 5,000 an
  hour.

## Verification

- `checks.schedule-watchdog` fails with the decision broken (§1): drop the
  in-flight test, and the queued case must dispatch and go red; drop a table
  row, and the coverage assertion names it.
- On p620 after the deploy: `systemctl --user list-timers` shows it, and a run
  of the service with `NOW` at a time past a cron logs a dry decision (a
  `--dry-run` flag that prints what it would dispatch).
