---
status: draft
issue: 1537
spec: spec/2026-10-31-1537-review-followups.md
coders:
  2: agy     # prose only; agy drafts docs well and needs no build
  3: codex   # one workflow file, shell logic; the session runs actionlint and the dispatch
reviewers:
  - codex    # owner asked for Codex and agy reviews of these changes
  - agy
---

# Plan: follow-ups from the 2026-10-31 review

Four pull requests, one per group. The decisions approved in the spec are:

- **A, `update.yml`.** Build each pinned package on its own. If one fails,
  `git checkout HEAD --` its file, which is found from `meta.position`. Open
  the pull request with the bumps that built, then end the run red, naming
  the updaters that failed and the packages that were reverted.
- **B, `omarchy-edge.yml`.** Run `readme-counts.sh --fix` just before
  "Publish the candidate". Add one sentence to CLAUDE.md §8. No edit to the
  README.
- **C, owe.** Add `env.NIX_CFLAGS_COMPILE = "-DRENDER_START_MS=30000"`,
  which uses upstream's `#ifndef` and needs no source patch. `checks.coexist`
  asserts that the line `owe-render has no socket after` is never logged.
  Correct the stale timing comment at `tests/coexist.nix:183-184`. Nothing
  is filed upstream.
- **D, the keyring paragraph.** Rewrite it to cover the separate keyring an
  app may create before the first unlock, and keyrings after `passwd`.

A and B are CI-gate changes. Open them for a human to merge, and never
admin-merge them (§11). C and D take the usual `--auto --squash`.

## Steps

Order: 1 (C), 2 (D), 3 (A), 4 (B). Each step is its own branch off a fresh
`main`. Read the `git pull --ff-only` status before cutting a branch, and
after any reset check `git merge-base origin/main HEAD` (§5).

1. **C. owe start wait.** Branch `fix/1537-owe-start-wait`.
   - a. `tests/coexist.nix`, after the `assert delta …` block (line ~200),
     before the final `print`, add:
     ```python
     # #1537: the late-start window kills a renderer owed cannot reach; never open it.
     late = machine.succeed("journalctl -b --no-pager | grep -c 'owe-render has no socket after' || true").strip()
     assert late == "0", f"owed opened owe's late-start window {late} time(s) (#1537)"
     ```
   - b. Lines 183-184: replace the comment with the measurement: "the last
     ten CI runs painted on tries 9-16, the slowest 16 of 24, the time spent
     in owed's shell enable/disable cycle after the renderer is ready
     (#1537)".
   - c. Commit a and b alone with a temporary subject and push. Open the PR
     as a draft. That CI run is the fail-first output: owe 0.2.13 stock logs
     `owe-render has no socket after 7000 ms` on the coexist guest (as in run
     41192695246). Save the failing assertion text.
   - d. `pkgs/apps/owe.nix`, after `doCheck = true;` (line 66), add:
     ```nix
     # CARRIED (#1537): owe >= 0.2.13 waits 7 s, then refuses IPC to a late renderer
     # and process_shell_handoff stops it. Wait the whole 30 s, as before #1535.
     # Drop when upstream stops killing a late renderer.
     env.NIX_CFLAGS_COMPILE = "-DRENDER_START_MS=30000";
     ```
   - e. `tests/AGENTS.md`, section "The owe one" (line ~454): add one
     paragraph. The #1537 assertion can fail only on a guest whose renderer
     needs more than 7 s. CI's coexist guest does (11.5 s), and a fast KVM
     guest would pass it with the bug present.

   Verify with `nix build .#owe -L`: the meson suite passes. Use the
   package tier, run only after both `vm-host-free.sh` sides print `free`
   and with load under 12 (§6). `checks.coexist` is a VM check: leave it to
   the PR's CI unless `gh run list` shows nothing in flight. Its log must
   show `owe-render ready after` and no late line. Squash to one commit with
   the real subject before marking the PR ready (§8).

   Traps: a hook may reformat the `.nix` file, so run `nix fmt` and read
   `git diff --stat` (§5). If a heredoc lands in an indented `''` string,
   nixfmt reindents the file (§5). Check `nix build`'s exit status, not its
   last line (§5).

2. **D. The keyring paragraph.** This step ships on this artifact branch,
   `fix/1537-review-followups`, so its PR links all three files.
   `docs/manual/security.md:134-140`: replace the paragraph with one that
   says:
   - With autologin, the keyring named *login* stays locked until the first
     lock-screen unlock, which opens it.
   - If an app (Chromium, for one) asked you to *create* a keyring before
     that first unlock, the keyring it made is separate and stays locked
     every boot. In Seahorse, delete it, or give it your login password and
     make it the default.
   - After `passwd`, the keyring keeps the old password. The next prompt
     asks for it once; Seahorse's *Change password* brings it in line.
   - The keyring stays encrypted, unlike upstream's (#1492). The existing
     opt-out line stays as it is.

   House style is in `docs/AGENTS.md`: short sentences, no hedging.
   Verify by building the docs check that `docs/AGENTS.md` names, and
   by `grep -n 'Seahorse' docs/manual/security.md`.

   Traps: none that build. agy can't build, so the session runs the check.

3. **A. `update.yml` keeps what built.** Branch `ci/1537-update-partial`,
   file `.github/workflows/update.yml`.
   - a. Lines 46-47, the bump step:
     `nix run .#update || echo "update_failed=true" >> "$GITHUB_OUTPUT"`.
     The `changed=` block below it is unchanged.
   - b. Lines 56-93, the build step:
     - Add `id: build`.
     - Keep the `mapfile` guard (§4: capture first, refuse on empty).
     - Replace the single `nix build` with a loop over `attrs`:
       ```bash
       nix build --impure --print-build-logs "$a" || failed+=("${a#.#}")
       ```
     - For each failed attr:
       - `pos=$(nix eval --raw "$a.meta.position") || die`
       - `file=${pos#*-source/}; file=${file%:*}`
       - Refuse unless `file` matches `pkgs/*` and exists.
       - `git checkout HEAD -- "$file"`
     - After the loop: `git diff --quiet` gives `changed=false`, otherwise
       `changed=true`. Write `failed=${failed[*]}` to `$GITHUB_OUTPUT`.
     - Don't `exit 1` in this step.
     - Fix the stale comments: "two small binary repacks" (~:69) and "Six
       is what…" (~:81-82). The set is ten; list it, or say "every package
       with an updateScript".
   - c. The PR step (line 96): change its `if:` to
     `steps.build.outputs.changed == 'true'`. Add a body line:
     `${{ steps.build.outputs.failed && format('Reverted, did not build: {0}. See the run log.', steps.build.outputs.failed) || '' }}`.
   - d. New last step, `name: Fail when anything did not update or build`,
     with `if: always() && (steps.bump.outputs.update_failed == 'true' || steps.build.outputs.failed != '')`.
     It runs `echo "::error::…"` naming both, then `exit 1`.

   Verify:
   - `nix run nixpkgs#actionlint -- .github/workflows/update.yml`.
   - **Fail first.** On scratch branch `scratch/1537-update-replay`, cut from
     `main`:
     - Restore `pkgs/apps/owe.nix` from `b484e18a~1`, so nix-update re-bumps
       it to 0.2.13 and its `postPatch` fails, as on 2026-10-31.
     - Downgrade `pkgs/apps/omacalc.nix` to its previous version and hash
       (`git log -p -- pkgs/apps/omacalc.nix`), so it bumps cleanly.
     - Commit. Run `gh workflow run update.yml --ref scratch/1537-update-replay`
       with the **current** `update.yml`, and capture that it opens no PR and
       goes red.
   - **Then the fix.** Cherry-pick step 3's commit onto the scratch branch
     and dispatch again. It must:
     - open a PR carrying omacalc only;
     - name owe as reverted;
     - end red.
   - Close that PR and delete both scratch branches after recording the run
     ids in the real PR.

   Traps:
   - Verify under bash, not zsh (§1).
   - `mapfile < <(cmd)` can't see `cmd` fail (§4).
   - A pipe hides the status of `nix build`, so don't pipe it (§1).
   - Don't put a skip-CI marker in any commit message or the PR body (§8).
   - Codex can't build or dispatch, so the session runs every check.

4. **B. Edge derives its own counts.** Branch `ci/1537-edge-counts`.
   - a. `.github/workflows/omarchy-edge.yml`: insert a step immediately
     before "Publish the candidate" (line 360), with publish's own `if:`:
     ```yaml
     - name: Write the README numbers this pin computes
       if: steps.pin.outputs.skip != 'true' && (steps.build.outcome == 'success' || steps.build2.outcome == 'success')
       # #1537: derived from edge's pin, never hand-edited; publish's `git add -A` takes it.
       run: .github/scripts/readme-counts.sh --fix
     ```
   - b. `CLAUDE.md` §8, in the paragraph beginning "Before a merge like
     this, run" (line 942), add: "After restoring `main`'s Omarchy pin on the
     merged tree, run `.github/scripts/readme-counts.sh --fix` and commit
     what it writes: those numbers are derived from the pin, so neither
     side's README is right for the other (#1537)."

   Verify:
   - `actionlint` on the workflow.
   - **Fail first**, by hand, in `git worktree add --detach
     /mnt/data/vmtest/1537-edge origin/edge`:
     - `git checkout origin/main -- flake.nix flake.lock`;
     - `.github/scripts/readme-counts.sh --check` prints `README.md says 41,
       the repository says 40`. Capture it.
   - **Then the fix.** In the same worktree, `--fix` writes 40 and
     `--check` passes.
   - Remove the worktree.
   - **Do not** dispatch `omarchy-edge` from the branch: it force-pushes
     `edge-candidate` and can promote to `edge`. The first scheduled run
     after merge is the live proof. The PR says so, and the session reads
     that run's step output.

   Traps:
   - A worktree flake sees only tracked files (§5).
   - `readme-counts.sh` needs the input in the store, and `nix flake
     archive` fetches it.
   - Don't edit the README.

## Tests

| Step | Command | Expected |
|---|---|---|
| 1 | `nix build .#owe -L` | exit 0, meson suite passes |
| 1 | PR CI `checks.coexist`, commit c | fails on the #1537 assertion |
| 1 | PR CI `checks.coexist`, final | passes; log has `owe-render ready after`, no late line |
| 1, 3, 4 | `nix fmt -- --ci`, `statix`, `deadnix` (cheap tier) | clean |
| 2 | docs check from `docs/AGENTS.md` | passes |
| 3 | `actionlint` | clean |
| 3 | `update.yml` dispatch on the scratch replay, before and after | no PR and red, then a PR with omacalc only and red naming owe |
| 4 | `readme-counts.sh --check` on the edge+main-pin worktree, before and after `--fix` | 41-vs-40 error, then pass |

Reviews: a fresh Opus agent gets this plan path and each PR's `git diff`.
Codex `review --base main` and agy `--mode plan` run per PR, one at a time,
read-only. Findings are verified before anything is acted on.

## Rollback

Each group is one squashed commit, so `git revert <sha>` restores the
previous behaviour:

- **C.** Upstream's 7 s wait returns.
- **D.** The #1526 paragraph returns.
- **A.** The all-or-nothing bump returns.
- **B.** Edge stops writing the counts.

Nothing deploys to a host, and nothing migrates state.
