---
status: approved
issue: 1602
intent: intent/2026-11-04-1602-edge-report-truth.md
---

# Spec: Edge's report says what happened, and a refused quattro commit is not an outage

## Design

Five changes. No gate moves: what may reach `edge` is decided by the same checks.

### 1. The report states three outcomes, from a script a check can test

The `report` job's inline shell moves to `.github/scripts/edge-report.sh`. Nothing
tests that logic today, and it's about to branch more. The job gains a sparse
checkout of `.github/scripts`, the same way `wait-idle` has one. `report` keeps
having no `continue-on-error`, so a script that can't read or write an issue fails
the run (§4).

| Run outcome | "not publishing" issue | "quattro is held back" issue |
|---|---|---|
| promoted, and the pin is upstream's newest | closed | closed |
| promoted on an older quattro through `from_candidate` | closed | **left as it is**, and none is filed |
| promoted on the fallback pin | closed | filed or updated |
| skipped, edge is already current | **closed** (today it's left open) | closed |
| anything else, edge did not publish | filed or updated, as today | untouched |

"Newest" is a new `prepare` output from the pin step. A `from_candidate` run keeps
the candidate's pin, so the step now also asks upstream for quattro's head and
compares; a failed lookup is `failed=quattro-sha`, as it is on a normal run. #1543
had to be reopened by hand for lack of this: a promotion on the old pin closed it
while the new commit was still red. On the older-pin row no refusal has been
measured, so nothing is filed, and the next scheduled run tests the newest commit
and settles the held issue either way.

The held issue:

- **Title:** `Omarchy quattro is held back`, fixed, so the lookup stays an exact
  match.
- **Label:** `omarchy-edge-held`, separate from `omarchy-edge`. The README and the
  manual link that label as "what broke", which a held commit isn't.
- **Milestone:** `Keeping the lights on` (§12).
- **First line:** `held-sig: <sha7>: <checks>`, so a new comment appears only when
  the refused commit or the checks change. Deduplication compares the newest line
  with that prefix across the body and all comments, for `edge-sig` too. Today it
  reads only the last comment, so any other comment would defeat it.
- **Wording:** says "needs a classification row" only when **every** named check
  is in a fixed list: `bin-ledger`, `etc-overlay`, `menu-actions`, `menu-conditions`,
  `menu-verbs`, `omarchy-package-ledger`, `skill-parity`, `stale-scripts`. Anything
  else, or no name at all, reads "upstream candidate failed; investigate".
- **Escalation:** one comment beginning `held-escalated:` once the issue is more
  than 20 h old, skipped if any comment already starts that way. The threshold is 20 h and not 24 h because the schedule is daily
  and a report lands at about the same time each day, so 24 h could slip to a third
  run, 48 h later. In practice it escalates at the second daily run.

### 2. Every signature names what failed

- `edge-build.sh` keeps one `try` for the generated checks, then, if that fails,
  takes the root failures from the log lines written since just before that `try`,
  so a red `omarchy` isn't named twice. It uses a new `failure-digest.sh --names <log>` mode, which reuses the existing
  awk that separates roots from cascades. The names are written as check names, with
  `nixarchy-` removed. If it finds no names, the entry stays `generated-checks`,
  which names the step. A name that doesn't match the classification list, such as
  `vm-test-run-nixarchy-session`, reads "investigate", which is the safe direction.
- `edge-build.sh` writes `failed=` on its two early exits as well, which today
  leave the signature empty.
- `pin2` writes `failed=fallback-pin` on error.
- `prepare` gets separate outputs: `held_by` (`build`'s names), `held_sha`, and
  `failed`. `failed` now lists later steps first, so a failure after a good
  fallback reports that step and not the earlier refusal:
  `candidate || build2 || pin2 || build || pin || merge || start`. When `build` and
  `build2` both fail, the signature names both.
- `verify` writes `failed=` after each red check rather than after the loop, writes
  it on its two early exits, and includes `promote` when the promotion step fails.
  Today a failed promotion reads `verify: failure`, and the `promote: not promoted`
  branch can't run for it.
- `report` writes a job result of `cancelled` as `timed out`, which is what it
  means there (the existing comment says so), and adds it after any names already
  written, so an earlier red check and a later hang both show.

### 3. The reason survives the run

**Failed runs vanish.** Of 14 runs named in the issues that I sampled, 8 return 404,
including one from today, while successful runs from the same hours remain. The newest
`failure` conclusion listed for this workflow is from 10-30, though the issues record
failures since. Nothing in this repo, `~/.config/nixos` or the skills deletes runs, so
the cause isn't established. Whatever it is, the reason can't live only in the log.

So the digest goes in the issue. `failure-digest.sh` adds a bounded `report` output of
at most 60 lines. Each issue uses the digest of what it reports:

| Issue state | Digest |
|---|---|
| held | a new step straight after `build`, run if `build` failed, which then moves the log aside so `build2` starts a fresh one. It's needed because a rescued job ends green and `if: failure()` skips the existing step |
| not publishing, `prepare` failed | the existing final step, which now sees only what came after the refusal |
| not publishing, `verify` failed | `verify`'s own digest step |

`edge-report.sh` puts it below the signature line in a `text` fence, so a signature
stays the first line.

### 4. `readme-counts` gets the fallback

`readme-counts.sh --fix` moves from its own step into `edge-build.sh`, after the
checks and only if they all passed. A count word the script doesn't know then fails
the attempt by name, and the existing fallback takes over. It needs `result`, which
that script has just built and git ignores. `Publish the candidate` still takes the
edit with `git add -A`.

`readme-counts.sh` edits with `sed -i` as it goes, so a refusal can leave a partial
README, and the fallback's throwaway commit would take it. On refusal `edge-build.sh`
runs `git checkout HEAD -- README.md` before exiting, which restores the throwaway
commit's copy, and only then does its trap undo that commit.

This is a deliberate behaviour change: a run that publishes nothing today would
publish `main` on the last good pin, while the refused commit is reported as held.
No unclassified change gets through: the fallback pin is what edge already ships.

### 5. A waiting carry is picked up, not deleted

A new `.github/scripts/edge-carry.sh` prints one of three answers, from
`git log origin/edge..origin/edge-candidate --not origin/main --format=%ae`:

| Answer | When | What the run does |
|---|---|---|
| `none` | no `origin/edge` or `origin/edge-candidate`, which keeps today's first-publish path; or nothing there; or only the bot's commits | as today |
| `carry` | a non-bot commit, and `origin/edge` is an ancestor of the candidate | starts from the candidate, keeping its pin, exactly as `from_candidate=true` does |
| `diverged` | a non-bot commit, and edge has moved past it | stops with `failed=candidate-diverged`, pushes nothing |

`--not origin/main` is what makes this work: a failed candidate contains `main`'s
merged commits, whose authors aren't the bot. `diverged` stops rather than
overwriting. It's an outage alert by design, naming the commit and the two ways out:
rebase the carry onto `edge`, or delete it from `edge-candidate`.

A carry keeps §8's existing rule: it pins the quattro commit it classifies. A carry
that forgets still fails as #1498 did, loudly, and the pin isn't moved for it, because
guessing which quattro a carry was written for is how it would get tested against the
wrong one. While a carry keeps failing, runs stay on its pin, and that's reported as
an outage until someone fixes or removes it.

**A known limit:** this trusts the author. A hand-made commit with the bot's own
identity reads as disposable. In the 46 commits on edge since 11-01, the bot's 36 and
the carries' 10 separate cleanly, and git's default identity is never the bot's. The
script carries a `shortcut:` comment saying so.

`from_candidate=true` stays for its existing use. §8's warning about a plain dispatch
deleting a carry is retargeted in the same PR.

### 6. The suspected race gets a barrier

`tests/restart-terminal-wrapped.nix` waits, bounded at 10 s, until each stand-in's
`/proc/<pid>/comm` shows its exec'd name before running the script. A stand-in that
never gets there fails with its own message. The comparison uses the first 15
characters, since `comm` truncates and `.ghostty-wrapped` is 16.

**This is still unproven as the cause of #1601.** The check's own sequence, without a
barrier, hit 260 of 260 on p620, including 60 of 60 pinned to one busy CPU. What the evidence does support:
the failed log shows `.ghostty-wrapped` signalled and `.kitty-wrapped` not, and the
script tests kitty first, so a miss that closes within milliseconds looks like exactly
that. The barrier is a few lines and costs nothing if the theory is wrong, and a
recurrence will now name the check and keep its excerpt.

## Coexistence

None of this reaches a machine: it's CI, and a test. Nothing changes in a module, an
option or a shipped file, so no fixture applies.

## Alternatives rejected

- **Soft-failing classification checks on edge.** It would stop the fallbacks, but an
  unclassified script or package could reach edge users. All three reviewers reject it.
- **Automatically accepting proposed rows.** Same loss. Proposing them for review is
  a separate later issue, per the intent.
- **A VM-check fallback.** A second round of VM time on p620, delivering nothing when
  `main` hasn't moved. Measure first, per the intent.
- **Per-check `try` in `edge-build.sh`.** One `nix build` per check gives up the proof
  slices and the single evaluation that `build-unless-proven.sh` exists for.
- **A build's output paths as the failure list.** A cascade has no output either, so
  one red `omarchy` would name every check. The log separates roots from cascades.
- **Saving a diverged carry to a new ref and publishing anyway.** More moving parts,
  and the carry still wouldn't be applied. Stopping is simpler and just as lossless.

## Risks

- **A stale carry stops edge.** An abandoned commit on `edge-candidate` now either
  fails its build or stops as `diverged`. That's an alert until someone removes it,
  which beats silently deleting real work.
- **A held issue nobody acts on.** It's quieter by design. The escalation is the
  mitigation, and it's only a comment.
- **Tee lag in the log offset.** The log is written through a process substitution, so
  a read could miss the last lines. The proof push after each slice takes seconds, and
  a miss degrades to naming `generated-checks`, which is still true.
- **Comment and issue noise from quattro moving.** Each newly refused commit adds a
  comment to one issue. That's bounded by the number of runs.
- **This run's report is replaced in one go.** A bug in `edge-report.sh` shows on the
  next edge run. It fails loudly, and the job-level check covers each row above.
- **Not fixed:** a held commit with an unchanged `main` still rebuilds and re-verifies
  on p620 each run, and only moves the date in the version string. It's existing
  behaviour and wasteful, not wrong, so it stays out of this change.

## Verification

All of it local before any push, per §6's tiers, and each new check shown failing (§1):

- **`checks.edge-report` (new, cheap):** the real script against a stub `gh`, one case
  per table row, plus label, deduplication, classification wording, escalation before
  and after 20 h, the digest in the body, and a `gh` failure failing the script. Breaks:
  restore today's fallback behaviour, drop the skip close, treat an older-pin promotion
  as newest, and treat an unknown check as classification. Each must go red. It also
  runs a third report after an escalation, with the same and with a changed signature,
  which must post no duplicate escalation or unchanged signature.
- **`checks.edge-carry` (new, cheap):** a real git repo for each answer, including a
  failed bot candidate with merged human `main` commits, which must read `none`, and
  each ref being absent. Break: remove `--not origin/main`.
- **`checks.failure-digest` extended:** `--names` against the existing fixtures, and the
  `report` output bound. Break: count cascades as roots.
- **`checks.restart-terminal-wrapped`:** still green, and still red when the
  `.kitty-wrapped` pattern patch is reverted. One deterministic, temporary §1 proof:
  hold the kitty stand-in with `(sleep 1; exec ./.kitty-wrapped ...) &`. That's red
  without the barrier and green with it. It goes in the PR and isn't kept, because it
  proves the barrier closes the gap, not that the gap caused #1601.
- **`README.md` on a refusal:** `checks.edge-report` also runs `edge-build.sh` with
  `nix` and `readme-counts.sh` stubbed. A stub that edits and then refuses must leave
  `README.md` as it was. Break: drop the restore.
- **`actionlint`,** and every `generated-checks.sh` target plus `grep-q-pipefail`,
  `nix fmt -- --ci`, `statix` and `deadnix`.
- **Not reachable locally:** the workflow's wiring only runs on GitHub. The first real
  proof is an edge dispatch after merge, and I'll read that run's report and outputs.
  Whether a timed-out job keeps its outputs can't be tested here either, so a timeout
  may still read `verify: timed out` with no name, which names the step.
