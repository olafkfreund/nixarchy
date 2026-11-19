---
status: approved
issue: 1858
intent: intent/2026-11-19-1858-nightly-vm-job-sequencing.md
---

# Spec: put the nightly's keyboard-boot behind install-class sequencing

## Design

Two chains of install-class jobs in `.github/workflows/nightly.yml`, so at
most two of those guests run at once:

- A (exists): `install` (about 3 min) → `install-iso-net` (about 19 min).
- B (new): `install-encrypted` (about 12 min) → `keyboard-boot` (about 19 min),
  through `needs: [install-encrypted]` and `if: always()` on `keyboard-boot`.

Timings are from run 44449120419. Chain B ends around minute 31, well before
`commit-independent` (about 52 min), which already sets when `digest`
starts. So the nightly does not get longer.

`microvm` stays unchained. It is not install-class: no disk install, and
its L2 guest boots in about 2 minutes.

Fix the two comments that describe the old ordering: the one on
`install-encrypted` ("only `install-iso-net`'s `needs` orders anything")
and the one on `install-iso-net` ("`keyboard-boot` and `microvm` are in no
chain. Measuring in #1858"). Record the load measurement from the intent.

## Alternatives rejected

- **A nightly participant in `vm-host-free.sh`.** It waits inside the job, so
  the wait spends the job's own timer. That shape already deadlocked
  install against edge `verify` (#1524). `needs:` waits before the job
  starts and costs nothing.
- **A concurrency group.** It keeps one pending job and cancels the next
  (§6), which turns over-subscription into a `cancelled`.
- **`keyboard-boot` after `install-iso-net` (one chain).** Same cap, but chain
  A would then run to about minute 41 while chain B sits idle. Splitting the
  work across both chains is shorter.
- **A check that counts unchained install-class jobs.** It needs a
  hand-kept list of which jobs are install-class, and that list fails open
  (§4). Left out. The start times in the next nightly are the evidence.

## Risks

- If `install-encrypted` hangs to its 90-minute cap, `keyboard-boot` starts
  at minute 90 and the nightly ends later. `keyboard-boot`'s own 120-minute
  timer only starts when it does, so no false timeout follows.
- `if: always()` also runs `keyboard-boot` when `install-encrypted` was
  cancelled by a host switch. That is wanted: it is the same rule chain A
  uses.

## Coexistence

Not user-facing config: a CI workflow only.

## Verification

- `actionlint .github/workflows/nightly.yml` is clean.
- `yq '.jobs.keyboard-boot.needs, .jobs.keyboard-boot.if'` prints
  `install-encrypted` and `always()`.
- `checks.nightly-digest` (it parses `nightly.yml`) still passes.
- Not run locally: the nightly itself. The next run's start times should
  show `keyboard-boot` starting when `install-encrypted` ends.
