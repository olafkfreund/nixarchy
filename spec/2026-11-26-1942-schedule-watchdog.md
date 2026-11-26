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

| workflow | cron (UTC) | dispatch input | counts as done | waits for |
|---|---|---|---|---|
| nightly.yml | `0 3 * * *` | | | |
| omarchy.yml | `0 4 * * *` | | | |
| update.yml | `0 5 * * *` | | | |
| review.yml | `0 6 * * *` | | | nightly, omarchy, update |
| omarchy-edge.yml | `0 6 * * *` | | | |
| flake-update.yml | `0 7 * * *` | | | |
| build.yml | `0 6 * * 1` | | also a `push` to `main` | |
| weekly.yml | `0 9 * * 0` | `job=stable-session` | job `stable-session` ran | |
| weekly.yml | `0 15 * * 0` | `job=install-stock-iso` | job `install-stock-iso` ran | |
| weekly.yml | `0 6 * * 1` | `job=propose` | job `propose` ran | nightly |

**Slot.** For each row, `T` is the most recent time at or before now, in UTC,
that the cron fired. The script understands `M H * * *` and `M H * * D` only,
and exits non-zero on any other shape, so a new kind of schedule is taught
rather than skipped. A slot older than 24 hours is never acted on: that bounds
catch-up after p620 was off, and it keeps a weekly job from being replayed days
late.

**Qualifying run.** A run counts for a slot only if it is on `main`, was
created at or after `T`, came from `schedule` or `workflow_dispatch` (or the
row's extra event), and did not end `cancelled`. For a `weekly` row, the named
job must also have run in it rather than been skipped, read from the run's job
list. Runs on other branches, pull-request runs, and runs cancelled before they
did anything therefore do not hide a miss.

**Decision**, per row, in table order:

1. Now is less than 45 minutes after `T`: not due. GitHub's own delay here ran
   1 to 16 minutes from 2026-11-13 to 2026-11-24. At a 15-minute tick, a miss is
   started at most an hour after its cron.
2. A qualifying run exists: done.
3. A run of that workflow on `main` is queued, waiting, requested, pending or in
   progress (any status but `completed`): leave it. A dispatch would evict a
   pending run (`cancel-in-progress: false`), or cancel the running one in
   `omarchy-edge` (`cancel-in-progress: true`, §8).
4. A row it waits for has no qualifying run for its own slot yet, or has one
   still running: leave it for a later tick. `review` and `propose` read what
   the night produced, so starting them first would report the night before.
5. The row is `nightly` and `vm-host-free.sh` does not print `free` for both
   `install` and `edge`: leave it. `nightly` starts two install VMs and never
   asks that script itself, so a catch-up run in the daytime could take p620
   past the two installs it holds (§6). The 03:00 run never meets this.
6. The watchdog already dispatched this slot (a marker file per workflow, input
   and `T` under `$XDG_STATE_HOME/schedule-watchdog/`): leave it. That stops a
   loop when a dispatched run is cancelled by hand.
7. Otherwise re-read the workflow's runs, and dispatch on `main` with its input
   only if step 3 still holds. This narrows the race with a run started at the
   same moment to the seconds between that read and the dispatch; it cannot
   close it, because GitHub has no conditional dispatch. Write the marker, and
   say so on stdout.

**Time.** The script runs under `TZ=UTC` and does its arithmetic on
`date -u +%s`, never on `%H` or `%M` (whose `08` and `09` are invalid octal in
`$(( ))`). Sunday is `0`, as in cron. The table's crons are GitHub's, which are
UTC, and p620 runs in local time with daylight saving.

**Cost and failure.** Runs are read once per workflow per tick
(`actions/workflows/<file>/runs?branch=main&per_page=50`), with one job list
per `weekly` run inside a live slot. That is about 10 requests a tick, 40 an
hour, against a limit of 5,000. A failed read skips that workflow's rows,
never dispatches for them, and makes the script exit non-zero after the other
rows are done, so the unit shows failed. `NOW`, `GH` and the state directory
can be overridden, for the check; `--dry-run` prints the decisions without
dispatching. It sets `GH_REPO` itself, because on p620 it runs from a store
path with no checkout. A desktop notification is sent once, after every row is
decided, and its failure is ignored: no session or no notification daemon must
not fail a tick that dispatched.

**`checks.schedule-watchdog`** runs the script against a stubbed `gh` and a
fixed `NOW`, and asserts:

- a daily job past the margin with no run is dispatched, with no input;
- within the margin (44 minutes) nothing is dispatched, and at 45 it is;
- a scheduled or hand-started run on `main` after `T` means no dispatch; a
  pull-request run, a run on another branch, or a cancelled run does not;
- a run in any non-`completed` status means no dispatch;
- a missed `weekly` job is dispatched with its `job` input; a newer `weekly`
  run in which that job was skipped does not count as its run;
- `review` is not dispatched while `nightly` for the same night is missing or
  running, and is once it has finished;
- a slot more than 24 hours old is not acted on, including the Sunday-to-Monday
  rollover and the slot just before midnight;
- a marker for the slot means no second dispatch;
- a failed read dispatches nothing for that workflow and exits non-zero, with a
  stub that fails one workflow's read and answers the others, so the rows after
  it are still decided;
- `nightly` is not dispatched while `vm-host-free.sh` reports a VM job;
- the same answers hold under `TZ=America/New_York`, at 08:xx and 09:xx, on a
  Sunday before 09:00 for the `0 9 * * 0` row, and across midnight;
- the table matches the workflow files: every `- cron:` line in
  `.github/workflows/` has a row and every row has its cron; every row's
  workflow declares `workflow_dispatch`; every `weekly` input is one of the
  `job` options; and each `weekly` job's `if:` names both its cron and its
  input. Each comparison names the row that disagrees (§4).

**The timer** is in `nixos_config`, on p620: a user service and timer every 15
minutes, running the script from the `nixarchy` input's store path with `gh`
and `jq` on its path. It authenticates with a fine-grained token limited to
`olafkfreund/nixarchy` with Actions read and write, held in agenix and passed
as `GH_TOKEN`. The owner creates that token. Not the owner's `gh` login: that
reaches every repository the owner can, and the script is updated whenever the
pin moves. On a dispatch it sends a desktop notification. Each dispatch is
also visible in the Actions list as `workflow_dispatch`.

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
- **The owner's `gh` login.** It needs no new secret, but it reaches every
  repository the owner can, held by code that changes with every pin move.

## Risks

- **p620 off or asleep:** no watchdog. Documented, not covered; p620 also hosts
  every runner, so a p620 outage stops more than this.
- **A late `nightly` overlaps a daytime install.** The same overlap the 03:00
  run would have had with a late install, and the install jobs already wait
  for `vm-host-free.sh`.
- **The token expires.** Reads fail, nothing is dispatched, and the unit
  fails, which `systemctl --user --failed` shows. The verify script on p620
  lists failed user units.
- **A late scheduled run arriving after the watchdog's dispatch.** If GitHub's
  scheduler is more than 45 minutes late rather than silent, both runs start.
  For `omarchy-edge` the later one cancels the earlier. The margin is the
  trade-off: longer costs every miss more time.
- **The table runs from `nixos_config`'s pin of nixarchy,** so a schedule
  changed on `main` is watched from the next deploy of p620. The check keeps
  the table and the workflows equal at every commit; #1946 shortens the lag.
- **API budget.** About 10 requests a tick, 40 an hour, against 5,000 an hour.
- **A run started in the same seconds as a dispatch.** Step 6 narrows it and
  cannot close it. For `omarchy-edge`, losing that race cancels the other run,
  which is then re-run by hand. This is weaker than the intent's "must not
  start a run over one in flight", and is recorded here for the owner.
- **An `omarchy-edge` run started by hand with `dry_run`** counts as that
  day's run; the API does not show a run's inputs. A dry run by hand is rare,
  and the next 06:00 run is unaffected.

## Verification

- `checks.schedule-watchdog` fails with the decision broken (§1): drop the
  in-flight test, and the queued case must dispatch and go red; drop a table
  row, and the coverage assertion names it.
- On p620 after the deploy: `systemctl --user list-timers` shows the timer, a
  `--dry-run` of the service prints a decision for every row, and one real
  dispatch of `review.yml` with the service's token proves the token can start
  a run.
