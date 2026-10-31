---
status: approved
issue: 1537
intent: intent/2026-10-31-1537-review-followups.md
---

# Spec: follow-ups from the 2026-10-31 review

Four groups, one pull request each, in this order. Groups A and B change CI
gates, so a human merges them (§11). C and D are ordinary.

The intent left three questions open and was approved without answering
them. This spec takes the recommended answer to each and marks it
**[decision]**. Change any of them here, at spec review.

## A. `update.yml` keeps the bumps that built

### Design

**[decision]** Keep what built. Revert a broken package's file before the
pull request is opened, rather than opening a pull request that carries a
known-broken bump. A pull request containing a broken package can't merge
until a human fixes it, and while it waits it holds every other bump
hostage, which is the failure this group exists to remove.

Changes, all in `.github/workflows/update.yml`:

1. **Bump step.** Use `nix run .#update || echo "update_failed=true" >>
   "$GITHUB_OUTPUT"`. The app already runs every updater and exits 1 if any
   failed (`flake.nix:1236-1240`, `|| rc=1`). Today `bash -e` turns that into
   "skip everything". A failed updater leaves its file unchanged, so carrying
   on is safe. The `changed=` logic stays as it is.
2. **Build step.** Build each attribute on its own instead of one batched
   `nix build`, so one failure neither hides nor cancels the others (§13).
   For each failure:
   - Find the package's file from `nix eval --raw .#<attr>.meta.position`,
     cutting everything up to `-source/`. All ten attributes in
     `.#update.pinned` resolve to `pkgs/apps/<attr>.nix` today.
   - `git checkout HEAD -- <file>` (`HEAD`, not the index; §5).
   - Add `<attr>` to `failed`.

   If `meta.position` gives no path inside the repo, the step refuses
   rather than guessing. Then it recomputes `changed` from `git diff
   --quiet`, and writes `changed` and `failed` to `$GITHUB_OUTPUT`.
3. **Pull request step.** Gate it on the build step's recomputed `changed`.
   Add a body line naming the reverted packages when `failed` is non-empty.
4. **New last step.** `if: always()`. It fails the job with `::error::`
   naming the updaters that failed and the reverted packages. The run still
   reads red in `review.yml`'s row, and the pull request that did open
   carries the good bumps.
5. **Stale comments.** Correct them: "two small binary repacks" and "Six is
   what .#update.pinned holds" become the current ten.

### Alternatives rejected

- **Open the pull request with everything and list the failures.** Less
  code, but the pull request is unmergeable until a human edits it, so one
  broken upstream still blocks the night's other bumps.
- **Use `continue-on-error` on the build.** It hides the failure, and §4
  says that is decoration unless something else is loud.

### Risks

- **A bump could span more than one file.** Today every pinned package is a
  single `pkgs/apps/<name>.nix`. If one gains a lock file beside it, the
  revert leaves that file bumped. The build of the reverted package would
  then fail on the next run and say so, which is loud, not silent.
- **Building ten packages one at a time is slower than one batched call.**
  The job has a 20-minute limit. The packages substitute or are small, so
  measure one run.

### Verification

Proof is by `workflow_dispatch` on a branch, since no `checks.*` reaches a
workflow's control flow.

- **Fail first.** On a scratch branch, make one updateScript `exit 1` and
  break another package's hash. Run the current `update.yml`: it opens
  nothing. Capture that run.
- **Then the fix.** Run the new workflow on the same breakage. It opens a
  pull request with the other bumps, names both broken packages, and ends
  red.
- `actionlint` passes on the file.

## B. Edge writes its own README counts

### Design

**[decision]** Derive edge's counts in edge's own workflow, with no rounding
in the README.

- **The step.** Add a step to `.github/workflows/omarchy-edge.yml` just
  before "Publish the candidate" (`:360`), with the same `if:` as publish.
  It runs `.github/scripts/readme-counts.sh --fix` and stages `README.md`.
  Publish already does `git add -A` and commits. The step runs after
  whichever pin won (quattro or the fallback), so one step covers both.
- **If it fails.** `--fix` refuses rather than guesses, and so does this
  step. Publish is then skipped, and the job's existing failure path updates
  the omarchy-edge issue (the `report` job reads `needs.prepare.result`).
- **CLAUDE.md §8.** Add one sentence to the paragraph about real edge→main
  merges: after restoring main's tag pin on the merged tree, run
  `readme-counts.sh --fix` and commit the result. Never edit a derived
  number by hand.
- **No README edit is needed today.** Main says 40, which is right for
  main's pin. Edge's 41 is right for edge's pin, and from now on edge's
  workflow writes it.

### Alternatives rejected

- **Round the Omarchy-derived figures.** That makes the README hold under
  both pins, but it gives up a check that has caught real drift (#831,
  #1142) and needs `readme-counts.sh` to stop checking five quantities.
- **Hand-edit the README on each sync.** That is what #1528 did, and it is
  the cause of this group.

### Risks

- **A merge conflict.** Merging main into edge (`:120`) can conflict on that
  README line when main's own count changes on a release bump. That already
  fails loudly as `merge-conflict`, and the documented recovery
  (edge-candidate plus `from_candidate=true`) applies.
- **Extra time.** `readme-counts.sh` runs a `nix flake archive`. That is
  seconds, against a job measured in tens of minutes.

### Verification

- **Fail first.** In a detached worktree (§5: `git worktree add --detach`),
  check out `origin/edge` with main's `flake.nix` and `flake.lock` pin
  restored, which is the shape of an edge→main merge. Run
  `readme-counts.sh --check` and capture `README.md says 41, the repository
  says 40`.
- **Then the fix.** `--fix` on that tree writes 40, and `--check` passes.
- **The workflow step.** Run `omarchy-edge` with `workflow_dispatch` and
  read the step's output on the candidate. The candidate's README must
  match what `--check` computes against its own lock.
- `actionlint` passes.

## C. owe gives a slow renderer its full start wait again

### Design

**[decision]** Restore the 30 s blocking wait through upstream's own hook.
Nothing is filed upstream; the owner can decide that separately.

- **The flag.** In `pkgs/apps/owe.nix`, add
  `env.NIX_CFLAGS_COMPILE = "-DRENDER_START_MS=30000";`.
  `src/daemon/supervisor.c:25-27` wraps the define in `#ifndef`, so this
  needs no source edit and can't stop matching on a bump.
- **Why it works.** With the start wait at 30 s and `RENDER_LATE_MS` also at
  30 s, a renderer either has its socket inside the wait or is stopped by
  upstream's own `socket never appeared` path. The late window, during which
  `owed_supervisor_send` refuses commands (`supervisor.c:236`) and
  `process_shell_handoff` kills the renderer (`main.c:309-324`), is never
  entered. This is the behaviour nixarchy shipped from #1153 to #1535.
- **The comment.** Two lines above the flag, starting `# CARRIED (#1537):`,
  name the kill path and say to drop the flag when upstream stops killing a
  late renderer.
- **The test.** Add an assertion to `tests/coexist.nix`, after first paint:
  `journalctl -b` holds no `owe-render has no socket after`. That line is
  logged only when the late window opens.

### Alternatives rejected

- **Accept the risk.** It is CI-only on fast GPUs, but CI is where every
  owe regression in this repo was found (#1359, #1437). A renderer killed
  mid-start there reads as a flaky coexist run, and a flaky pass is a
  deleted bug report (§10).
- **A `substituteInPlace` on `main.c`.** That is the carry shape that broke
  on 0.2.13.

### Risks

- **owed blocks for up to 30 s on a renderer that never starts.** It did so
  before #1535 too. Upstream's comment notes that a restart then misses the
  owe CLI's 10 s reply timeout. That is already true of every release we
  shipped before #1535.
- **The assertion can't fail on a fast guest.** If a guest is fast enough
  to start the renderer in under 7 s, the late window never opens. §3
  applies here: CI's coexist guest is the slow one (11.5 s in run
  41192695246), and that is the variable this assertion depends on.
  `tests/AGENTS.md` gets one line saying so.

### Verification

- **Fail first.** Build `checks.coexist` with the new assertion and without
  the flag. The guest logs `owe-render has no socket after 7000 ms`, as in
  run 41192695246, and the assertion fails. Capture that.
- **Then the fix.** With the flag added, the log shows `owe-render ready
  after ~11000 ms` and no late line, and the check passes. Because it is a
  VM check, it runs locally only when `gh run list` shows nothing in flight
  (§6). Otherwise the pull request's CI is the first run, and the
  fail-first output comes from a CI run of a commit holding only the
  assertion.
- `nix build .#owe` passes, including the meson suite. `test/supervisor.c`
  compiles with the same flags.

## D. The keyring note, and the coexist timing comment

### Design

- **`docs/manual/security.md`.** Replace the paragraph added in #1526 with
  one that says:
  - With autologin, the keyring named *login* stays locked until the first
    lock-screen unlock, which opens it.
  - If an app asked you to *create* a keyring before that first unlock, the
    keyring it created is separate and stays locked every boot. Fix it in
    Seahorse: delete that keyring, or give it your login password and make
    it the default.
  - After `passwd`, the keyring still has the old password, so the next
    prompt asks for it once. Seahorse's *Change password* brings it in
    line.
  - The opt-out option, unchanged.
- **`tests/coexist.nix:183-184`.** State the current measurement: the last
  ten runs landed at tries 9–16, the slowest 16 of 24. Leave `range(24)` as
  it is. The comment points at owed's shell enable/disable cycle, not
  renderer start, as where the time goes. Group C touches this file too, so
  this edit ships in C's pull request.

### Alternatives rejected

- **Create the login keyring at install.** That would stop an app from ever
  creating a separate one, but it is a behaviour change with its own
  coexistence questions (§14), for a docs-sized problem.

### Risks

None to code. One claim is not measured: that Chromium-first leaves a
separate keyring. It comes from gnome-keyring 50.0 source
(`gkd-login.c:192-230`, `gkd-secret-create.c:121-124`), verified by the
review. A row in `tests/AGENTS.md` names it as a hole tested by hand.

### Verification

The page builds in the docs check that `docs/AGENTS.md` names. Prose has no
fail-first.

## Coexistence

- **C.** Changes only owe's own binary.
- **A and B.** CI only.
- **D.** Documents behaviour the user's own `security.pam` settings already
  override; no option default changes.

`tests/coexistence/fixtures.nix` needs no fixture, because no option a user
sets is touched.
