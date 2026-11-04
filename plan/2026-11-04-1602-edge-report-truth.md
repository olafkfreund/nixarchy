---
status: draft
issue: 1602
spec: spec/2026-11-04-1602-edge-report-truth.md
coders:
  1: codex    # small, tricky git logic with a real-repo test
  2: codex    # awk reuse and a heredoc output, in a script that must never fail a job
  3: codex    # log offsets and restore order, where a slip reads as a pass
  4: coder    # the largest step: a new script and its stubbed test
  5: coder    # workflow wiring across five places, against steps 1-4's contracts
  6: coder    # a few lines in one test, written in a Nix '' string
  7: agy      # prose across four files, mechanical once the behaviour is fixed
reviewers:
  - codex     # read the two earlier drafts' logic most precisely
  - agy       # found the state and dedupe gaps in the spec
---

# Plan: Edge's report says what happened, and a refused quattro commit is not an outage

Work in `/mnt/data/vmtest/wt-1602`, branch `fix/1602-edge-report-truth`.

## Decisions carried from the approved spec

- **No gate moves.** What may reach `edge` is decided by the same checks. Soft-failing
  a classification check is rejected.
- **Five report outcomes**, in this order of evaluation (`PROMOTED` first asks the
  remote, as the job does today):

  | Run | "not publishing" | "held back" |
  |---|---|---|
  | promoted, not fallback, `NEWEST=true` | closed | closed |
  | promoted, not fallback, `NEWEST` not true | closed | as it is; none filed |
  | promoted, fallback | closed | filed or updated |
  | `PREPARE=success`, `SKIP=true` | closed | closed |
  | anything else | filed or updated | untouched |

- **Held issue:** title exactly `Omarchy quattro is held back`; label
  `omarchy-edge-held`; milestone `Keeping the lights on`; first line
  `held-sig: <sha7>: <checks>`.
- **Classification wording** only when every name is in `bin-ledger etc-overlay
  menu-actions menu-conditions menu-verbs omarchy-package-ledger skill-parity
  stale-scripts`. Otherwise, and with no names, "upstream candidate failed;
  investigate".
- **Dedupe:** the newest line with the prefix (`edge-sig:` or `held-sig:`), across
  the body and all comments, in comment order.
- **Escalation:** one comment starting `held-escalated:`, when the issue is more than
  72000 s (20 h) old and no comment already starts that way.
- **Digest in the issue,** below the signature, in a `text` fence: held uses the
  refused attempt's digest; `prepare` failure uses the final digest; `verify` failure
  uses `verify`'s.
- **`readme-counts`** runs inside `edge-build.sh` after all checks pass. On refusal,
  `git checkout HEAD -- README.md` before exit.
- **Carry detection** by author; a carry keeps its pin (§8), and `diverged` stops the
  run and pushes nothing.
- **Barrier** in the restart test, bounded at 10 s, comparing 15 characters of `comm`.

## Steps

Commit after each step, naming it. Each deviation updates this file in the same commit.

1. **`.github/scripts/edge-carry.sh` (new), `tests/edge-carry.nix` (new),
   `flake.nix` near `:1872` (add `"edge-carry"` beside `"edge-promote"`).**
   Prints exactly one of `none`, `carry`, `diverged`; exits non-zero only on a git
   error. Takes no arguments and reads `origin/edge`, `origin/edge-candidate`,
   `origin/main`:
   - either of `origin/edge` or `origin/edge-candidate` absent → `none`;
   - `authors=$(git log origin/edge..origin/edge-candidate --not origin/main --format=%ae)`,
     captured first (§4). No line other than
     `41898282+github-actions[bot]@users.noreply.github.com` → `none`;
   - otherwise `git merge-base --is-ancestor origin/edge origin/edge-candidate` → `carry`,
     else `diverged`.

   Add `# shortcut: trusts the author; a hand-made commit with the bot's identity reads
   as disposable. Upgrade to a recorded last-pushed SHA if that ever happens.` Follow
   `tests/edge-promote.nix`'s real-git setup, with `refs/remotes/origin/*` made by
   `git update-ref`. Cases: each ref absent; candidate equal to edge; bot commits only;
   **a bot candidate containing a merged human `main` commit, must be `none`**; a human
   carry on edge; a human merge commit; a human carry with edge moved past it.
   → verify: `nix build .#checks.x86_64-linux.edge-carry`. **§1 break:** remove
   `--not origin/main`; the merged-`main` case goes red.
   Traps: `git add` new files before building (§5). `nix fmt` then read `git diff --stat`
   (§5, the hook). No heredoc in the `''` string; use `printf`.

2. **`.github/scripts/failure-digest.sh`, `tests/failure-digest.nix`.**
   - `--names <log>` as `$1`: prints one root name per line and nothing else, with the
     leading `nixarchy-` removed, then exits 0. Reuse the existing awk and the `R`
     rows, and don't call `nix log`. Set `trap 'exit 0' ERR` in this mode, since the
     default trap prints to stdout, which the caller reads as names. `<log>` may be
     `/dev/stdin`.
   - In the default mode, after the digest is written, add a `report` output with a
     random delimiter: at most 60 lines (`tail -n 60`), each cut to 300 characters.
     Keep the existing `digest=` line unchanged, since the test matches it with `grep -qx`.
   - Add to the test: `--names` on `c-cascade.log` lists only the root; on `d-clean.log`
     prints nothing and exits 0; the `report` output is present and its body is at most
     60 lines.
   → verify: `nix build .#checks.x86_64-linux.failure-digest`. **§1 break:** make the awk
   emit `R` for cascades; the `c-cascade` names case goes red.
   Traps: the script must always exit 0 (its header says so). The digest still appends
   to `GITHUB_STEP_SUMMARY`.

3. **`.github/scripts/edge-build.sh`.**
   - Before `try generated-checks`: `log=${RUNNER_TEMP:-/tmp}/build.log` and
     `offset=$(wc -l <"$log" 2>/dev/null || echo 0)`.
   - After it, if `generated-checks` is in `$failed`: `names=$(tail -n +$((offset + 1))
     "$log" | .github/scripts/failure-digest.sh --names /dev/stdin)`. If `omarchy` is
     already in `$failed`, drop lines matching `^omarchy-edge-`. If names remain, replace
     the `generated-checks` word in `$failed` with them, space-separated. Otherwise leave it.
   - Both early exits (`generated-checks.sh failed`, `only N generated checks`) write
     `failed=generated-checks-list` first.
   - After the checks, when `$failed` is empty, run `.github/scripts/readme-counts.sh
     --fix`. On refusal: `::error::`, `git checkout HEAD -- README.md`, and
     `failed=readme-counts`.
   → tested in step 4, whose `edge-report` check drives this script.
   Traps: §5, `git checkout HEAD --` and not `git checkout --`. The script runs with
   `set -uo pipefail`, no `-e`, so check each status yourself. The EXIT trap undoes the
   throwaway commit, so the restore must run before exit.

4. **`.github/scripts/edge-report.sh` (new, executable), `tests/edge-report.nix` (new),
   `flake.nix` (add `"edge-report"` beside `"edge-carry"`).**
   Moves the inline shell from `omarchy-edge.yml:555-609`, keeping its comments that
   still apply. `set -euo pipefail`, no `continue-on-error` anywhere (§4). Reads from the
   environment: `PREPARE WAIT VERIFY CANDIDATE SKIP PROMOTED FALLBACK NEWEST
   PREPARE_FAILED HELD_BY HELD_SHA VERIFY_FAILED RUN_URL PREPARE_DIGEST HELD_DIGEST
   VERIFY_DIGEST GH_REPO`, and `EDGE_REPORT_NOW`, defaulting to `date +%s`, for the test.
   - Implement the outcome table above, with two small functions: one finds an open issue
     by label and exact title, and `post` files or comments with deduplication.
   - Signature: `prepare: X`, and when `HELD_BY` is set and differs from `X`,
     `prepare: fallback also red: X; quattro red: HELD_BY`. A `cancelled` job result reads
     `timed out`, appended after any names: `verify: options-a; timed out`.
   - Every first line stays alone on line 1; the digest follows a blank line, in a `text`
     fence, and is left out when empty.
   - `gh label create <label> --force` before filing, as today.

   `tests/edge-report.nix`: follow `tests/vm-host-free.nix` with a stub `gh` that logs its
   arguments and serves fixture JSON, and fails when `$FIX/fail` exists. One case per table
   row, and: a held issue that exists vs. doesn't; an unchanged and a changed `held-sig`;
   classification wording for all-listed names; "investigate" for one unlisted name and
   for none; escalation at 71999 s and 72001 s, then a further run with the same and with a
   changed signature, with no duplicate; a human comment after the signature doesn't defeat
   dedupe; the digest in the body; a `gh` failure failing the script; `cancelled` wording.

   It also drives `edge-build.sh`, in a scratch git repo with a copied script tree and
   stubbed `nix`, `generated-checks.sh`, `build-unless-proven.sh` and `readme-counts.sh`:
   a root failure in the log becomes its name in `failed=`; a `generated-checks` failure
   with no root stays `generated-checks`; a red `omarchy` isn't named twice; both early
   exits write `failed=`; a readme stub that edits and refuses leaves `README.md`
   byte-identical and writes `failed=readme-counts`; a readme success keeps its edit.

   It also asserts wiring, the part no local run can reach: each variable the script reads
   has a `VAR: ${{` line in the workflow's `report` step.
   → verify: `nix build .#checks.x86_64-linux.edge-report`. **§1 breaks, each must go red,
   each proven to land with `git diff`:** (a) file the "not publishing" issue on fallback;
   (b) drop the close on skip; (c) treat `NEWEST` as always true; (d) treat an unknown name
   as classification; (e) dedupe on the last comment only; (f) drop the README restore;
   (g) remove one env line from the workflow.
   Traps: `red()` helpers can be a green light (`tests/AGENTS.md`, #1524): every break runs
   by hand against the real check. No `''${` slips: escape as `''${` in the `''` string, and
   `\$` isn't an escape there (§5). Use `printf`, not heredocs (§5). `gh --jq` renders null
   as empty (§13). Stub-only tests can't vary a real `gh` flag, so check each flag with
   `gh issue list --help` once.

5. **`.github/workflows/omarchy-edge.yml`.**
   - **Outputs, `:47-51`:** add `newest: ${{ steps.pin.outputs.newest }}`,
     `held_by: ${{ steps.build.outputs.failed }}`, `held_sha: ${{ steps.pin.outputs.sha }}`,
     `held_digest: ${{ steps.held_digest.outputs.report }}`,
     `digest: ${{ steps.digest.outputs.report }}`. Replace `failed` with
     `steps.candidate.outputs.failed || steps.build2.outputs.failed ||
     steps.pin2.outputs.failed || steps.build.outputs.failed || steps.pin.outputs.failed ||
     steps.merge.outputs.failed || steps.start.outputs.failed`.
   - **`start`, `:106`:** when `FROM_CANDIDATE` isn't `true`, run `edge-carry.sh`, captured
     first. `diverged` → `failed=candidate-diverged` and an `::error::` naming both ways out,
     then `exit 1`. `carry` → use the candidate as `from_candidate` does, and log it.
     Write `from_candidate=true|false` as a step output.
   - **`pin`, `:183-195`:** env from `steps.start.outputs.from_candidate`. Always ask
     upstream, captured, with the existing refusal for a failure or non-SHA. Keep
     `sha=$HAVE` for a candidate start. Write `newest=true|false` from `sha = upstream`.
     The skip condition at `:205` stays as it is.
   - **New step after `build`, `id: held_digest`:** `if: steps.build.outcome == 'failure'
     && steps.pin.outputs.skip != 'true'`, `continue-on-error: true`, runs
     `failure-digest.sh`, then moves `$RUNNER_TEMP/build.log` to `build-refused.log`.
   - **`pin2`:** `trap 'echo "failed=fallback-pin" >> "$GITHUB_OUTPUT"' ERR`.
   - **Delete the `Write the README numbers` step, `:370-375`.**
   - **`verify`, `:449`:** `failed: ${{ steps.vms.outputs.failed || (steps.promote.outcome
     == 'failure' && 'promote') || '' }}`; add `digest: ${{ steps.digest.outputs.report }}`.
     Write `failed=` after each red check. The two `options` exits write
     `failed=options-list`.
   - **`report`, `:538-609`:** add a sparse checkout of `.github/scripts`, as `wait-idle`
     has, and replace the inline shell with `run: .github/scripts/edge-report.sh`, adding
     the new env.
   - **`:14`, the job diagram comment:** still correct; leave it.

   → verify: `nix run nixpkgs#actionlint -- .github/workflows/omarchy-edge.yml`,
   `checks.edge-report`'s wiring assertion, and `grep -rn 'steps.counts' .github/` empty.
   Traps: `outcome` not `conclusion` for a `continue-on-error` step, as the file already
   does. `readme-counts` is named in `tests/` or docs only as a script; grep before deleting
   the step (§4, widening a format). A repeated key in `GITHUB_OUTPUT`: last wins. The
   `failed` chain's `||` treats an empty output as false, which is what's wanted.

6. **`tests/restart-terminal-wrapped.nix:18-22`.** Between starting the stand-ins and
   running the script, for each pid and name, wait up to 10 s (100 × `sleep 0.1`) until
   `/proc/$pid/comm` equals `$(printf %.15s "$name")`. On timeout, print which stand-in
   never exec'd and `exit 1`.
   → verify: `nix build .#checks.x86_64-linux.restart-terminal-wrapped`. **§1 breaks:**
   (a) revert the `.kitty-wrapped` patch in `pkgs/omarchy/default.nix:510-514`, red;
   (b) temporarily hold kitty with `(sleep 1; exec ./.kitty-wrapped -c '...') &`: red with
   the barrier removed, green with it. Both go in the PR, neither is kept.
   Traps: `.ghostty-wrapped` is 16 characters and `comm` truncates at 15. `$(…)` is literal
   in a `''` string, but `${` isn't (§5).

7. **Docs.**
   - `AGENTS.md:977-985`: a plain run no longer deletes a carry. Retarget to what's true:
     the run picks up a descending carry and keeps its pin, stops on a diverged one, and
     trusts the author. Don't renumber; keep `from_candidate` for a hand-resolved merge.
   - `AGENTS.md` §13: one bullet: a run named in an issue can 404, so the digest in the
     issue is the evidence. The cause isn't established; say so.
   - `tests/AGENTS.md`: append `## The edge report and carry checks (#1602)`: what each
     covers, and that the workflow's wiring is only asserted by name, its first real run
     being after merge.
   - `docs/manual/omarchy-channels.md:56-59` and `README.md:645-648`: a commit edge refuses
     is reported by a calm `omarchy-edge-held` issue; `omarchy-edge` means edge didn't
     publish. Keep it short and in the house voice.
   → verify: read the diff; `readme-counts.sh --check`, `doc-options` and the docs checks
   are in step 8's tier.
   Traps: `CLAUDE.md` is a symlink to `AGENTS.md`; edit `AGENTS.md`.

8. **Everything local, then the PR (the session does this).**
   - Cheap tier, one at a time under `flock /mnt/data/vmtest/codex-build.lock`: every
     `generated-checks.sh` target plus `grep-q-pipefail` and `failure-digest`; `nix fmt --
     --ci`, `statix`, `deadnix`, `actionlint`. Confirm `edge-report` and `edge-carry` are in
     the generated list. Package tier for `omarchy` when its gate prints `free` (§6).
   - No VM check is reachable by this change, and none is run. Say so in the PR.
   - Rebase check: `git merge-base origin/main HEAD` is what's expected (§5).
   - Push (fast-forward only), open the PR linking all three artifacts, with the §1 red
     output and which steps codex, agy and the coder did, then comment `@codex review`.
     Use `Refs #1601` and `Closes #1602`, each on its own (§8). No skip-CI marker in the
     body (§8).
   - **Stop for the owner on merge:** it edits a workflow (§11).

9. **After merge.** Dispatch `omarchy-edge` once with no input, and read that run's report
   step, outputs and issues against the table. Quattro may be green by then, in which case
   the fallback path waits for a real refusal, and the PR's follow-up comment says which
   rows were seen. Post a bus note only if something cost time.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.edge-carry` | green; red on its break |
| `nix build .#checks.x86_64-linux.failure-digest` | green; red on its break |
| `nix build .#checks.x86_64-linux.edge-report` | green; red on all seven breaks |
| `nix build .#checks.x86_64-linux.restart-terminal-wrapped` | green; red on both breaks |
| `nix run nixpkgs#actionlint -- .github/workflows/omarchy-edge.yml` | no findings |

**Not run locally:** the workflow itself, which only runs on GitHub; whether a timed-out job
keeps its outputs. Step 9 is the first real run.

## Rollback

Revert the squash commit. The workflow then returns to its inline report, and
`omarchy-edge-held` issues stop being touched, so close any open one by hand. No state lives
outside GitHub issues, and `edge` and `edge-candidate` are unaffected by a revert.
