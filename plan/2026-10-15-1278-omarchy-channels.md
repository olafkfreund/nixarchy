---
status: approved
issue: 1278
spec: spec/2026-10-15-1278-omarchy-channels.md
---

# Plan: Omarchy edge and dev channels, separate from the nixpkgs channel

## Approved decisions (from the spec; implement against these)

- **A channel is the nixarchy branch the user's flake follows.**
  - stable is `github:olafkfreund/nixarchy/release` (unchanged).
  - edge is `github:olafkfreund/nixarchy/edge`.
  - dev is the edge URL, plus two lines in the user's `flake.nix`: a top-level
    `omarchy = { url = "git+file://<abs path>"; flake = false; };` and, inside
    the `nixarchy = {` block, `inputs.omarchy.follows = "omarchy";`.
  - The nixpkgs axis (`nixpkgs.url`, `inputs.home-manager.url`) and the Omarchy
    axis (`nixarchy.url`, the dev lines) touch disjoint lines. Switching one
    never edits the other's.
- **`edge` is `main`, plus three things:**
  - `omarchy.url = "github:basecamp/omarchy/<40-hex quattro SHA>"`;
  - `omarchyVersion = "edge-<YYYYMMDD>-<sha7>"`;
  - carry commits.

  `main` gets **no** version conditionals.
- **`edge` only fast-forwards.** Merge `origin/main` into it; never rebase,
  never force-push (CLAUDE.md §11).
- **Read the user's choice from `flake.nix`, never the lock and never a state
  file.** Unknown shapes are `custom` and are refused, not rewritten.
- **CLI:** a subcommand of the existing
  `pkgs/omarchy/nix-bin/nixarchy-channel`:
  ```
  omarchy [stable|edge|dev [PATH]|--current]
  ```
  plus `--current` for the nixpkgs half. Upstream's `omarchy-channel-current`
  and `omarchy-channel-set` delegate to it, and `rc` is refused.
- **Menu:** `update.channel.{stable,edge,dev}` become the Omarchy channel
  (`rc` stays hidden). A new parent, `update.nixpkgs.{stable,unstable}`,
  carries today's nixpkgs rows.
- **Nothing goes to cachix from edge.** Edge's VM checks run only when CI is
  idle. Failures update one rolling issue labelled `omarchy-edge`.
- **Users never see Edge before `edge` exists.** Merge order is:
  1. PR 1 (workflow);
  2. seed `edge`;
  3. PR 2 (switcher, menu, reporting, docs).

## Steps

### PR 1: the publishing machinery (this branch, `feat/1278-omarchy-channels`)

1. **`.github/scripts/edge-promote.sh` (new).**
   - Interface: `edge-promote.sh <remote> <candidate-sha> <expected-edge-sha>`.
   - Fetch `refs/heads/edge`. Refuse (exit 1, with the reason on stderr) if:
     - the remote head is not `<expected-edge-sha>` (stale; `edge` moved since
       `prepare`). An absent `edge` counts as the expected value `none` for the
       first publish;
     - `<expected-edge-sha>` is not an ancestor of the candidate (not a
       fast-forward).
   - Otherwise: `git push <remote> <candidate>:refs/heads/edge`, a plain push,
     never `-f` or `--force-with-lease`.
   - The gate result itself is the workflow's `needs:`/`if:`, not the script's
     job.

   **New check: `tests/edge-promote.nix`.** A `runCommand` with `git` and
   `coreutils` that builds a local bare remote. Cases:
   - (a) a fast-forward advances `edge`;
   - (b) a candidate on a diverged branch is refused and `edge` is unchanged;
   - (c) a stale expected head is refused and `edge` is unchanged;
   - (d) the first publish with `none` creates `edge`.

   Register `"edge-promote"` in `uniformChecks` (`flake.nix:1866`); it takes
   `{ inputs, pkgs }`.

   **Verify:**
   ```
   nix build .#checks.x86_64-linux.edge-promote
   ```
   - Red proof 1: delete the ancestor test and show (b) fails.
   - Red proof 2: delete the head comparison and show (c) fails.

   **Traps:**
   - §5: `git add` before evaluating.
   - Count failures and don't stop at the first. A failing case must print its
     name.
   - git in the sandbox needs `HOME`, `user.name` and `user.email` set.
   - `readme-counts.sh` may derive a check count. If it goes red, teach it the
     word in the same PR (§4).

2. **`.github/workflows/omarchy-edge.yml` (new).** Daily at `0 6 * * *`, after
   `omarchy.yml`'s 04:00, plus `workflow_dispatch`. Top-level
   `concurrency: { group: omarchy-edge, cancel-in-progress: true }`.

   **`prepare`** job: `ubuntu-latest`, `timeout-minutes: 45`. Reuse
   `./.github/actions/setup-nix` and the pull-only cachix step from
   `omarchy.yml:28-37`, with `skipPush: true`.
   1. Check out with `fetch-depth: 0`. Record
      `expected=$(git ls-remote origin refs/heads/edge | cut -f1)`, or `none`.
      Start from `origin/edge` if it exists, else `origin/main`. Then
      `git merge --no-edit origin/main`; on conflict, fail and name the files.
   2. Resolve `sha` with:
      ```
      gh api repos/basecamp/omarchy/commits/quattro --jq .sha
      ```
      Refuse an answer that is not 40 hex characters (the `omarchy.yml:54`
      lesson).
   3. Skip the rest (output `skip=true`) when `sha` equals the SHA in edge's
      `flake.nix` **and** `origin/main` is already an ancestor of `edge`.
   4. Rewrite `omarchy.url` and `omarchyVersion` with sed, then prove the two
      agree the way `omarchy.yml:84-98` does. Run `nix flake update omarchy`.
   5. Build. The cheap checks are built **separately** (§13: one eval error
      kills a batch), recording each result:
      - `nix build .#omarchy --print-build-logs`;
      - `menu-verbs`, `bin-ledger`, `skill-parity`, `panel-loaders`,
        `review-pins`, `stable-eval`, `options`.
   6. Briefings, each with a fallback line (copy the shape from
      `omarchy.yml`'s steps), written to `$GITHUB_STEP_SUMMARY` and to an
      output for the issue. Compare against `release`'s pin:
      - `.github/scripts/omarchy-package-delta.sh`;
      - `omarchy-config-delta.sh`;
      - `omarchy-patched-files.sh`.
   7. Commit `Edge: Omarchy quattro <sha7> on main <main sha7>` and push to
      `refs/heads/edge-candidate`. The candidate ref may be force-pushed: it is
      a scratch ref nobody follows. Say so in a comment.

   **`verify`** job: `needs: prepare`,
   `if: needs.prepare.outputs.skip != 'true'`, self-hosted. Same runner labels
   as `install-check.yml`'s VM jobs; copy them, don't guess.
   1. Wait for idle: loop on
      ```
      gh run list --limit 10 --json status,databaseId
      ```
      excluding this run's own id, sleeping 5 min until nothing else is
      in flight. Give up after 3 h with a clear failure (the §6 tier rule).
   2. Build `session`, `coexist` and `plugin` from `edge-candidate`, one
      `nix build` each.
   3. If all are green, run
      `.github/scripts/edge-promote.sh origin <candidate> <expected>`.

   **`report`** job: `needs: [prepare, verify]`, `if: always()`.
   - Find the open issue labelled `omarchy-edge` (create it if absent, with
     that label).
   - On failure, comment only when the failure signature (step + first failing
     check) differs from the issue's last comment.
   - On a promote, close it.
   - It must fail loudly if it cannot read or write the issue (§4: a
     `continue-on-error` step must be loud elsewhere).

   **`weekly.yml`:** after "Boot a session on nixos-26.05" (`:107`), add the
   same step on a checkout of `edge`, skipped if `edge` does not exist. This is
   the 26.05+edge boot.

   **Verify:**
   - `nix run nixpkgs#actionlint -- .github/workflows/omarchy-edge.yml .github/workflows/weekly.yml`.
   - Check that every action pin matches one already used in the repo.
   - Check that `.github/scripts/generated-checks.sh` still classifies
     `edge-promote` as built on pull requests (§4).

   **Traps:**
   - §8: no skip-CI marker anywhere in messages or the PR body.
   - §11: a CI-gate change, which the owner merges. The PR body asks them to
     create the `omarchy-edge` label and to confirm `GITHUB_TOKEN` can push
     `refs/heads/edge` (branch protection is unverified).
   - §13: `gh --jq` renders a null as empty, so don't `read` it into fields.

### Seeding `edge` (carry commits on branch `edge`, not merged into main)

3. **Pin `quattro` and get `.#omarchy` building.** Work in a new worktree
   `/mnt/data/vmtest/wt-edge`, branched from `origin/main` as `edge`.
   - Apply step 2's rewrite by hand: pin the current `quattro` SHA and set
     `omarchyVersion = "edge-<date>-<sha7>"`.
   - Build `.#omarchy`. Package-tier rule (§6): no p620 system build running,
     and the 1-minute load below 12; check with `uptime` and the anchored
     `pgrep` first.
   - Fix each failing `--replace-fail` anchor and `.patch` reject as its own
     carry commit, subject `Edge: <what and why>`. Expected first carries:
     - drop `1153-owe-video-backgrounds.patch` and
       `1155-panel-loaders-kept.patch` (already in `quattro`);
     - drop the `#1153` `omarchy-bar-text-color` edit
       (`pkgs/omarchy/default.nix:551-565`; `data/bin-ledger.nix:164` says the
       file is deleted on `quattro`).

   **Verify:** `nix build .#omarchy` succeeds. For each dropped patch, show
   that its hunk is already present in the `quattro` source (`grep`).

   **Traps:**
   - Never weaken `--replace-fail` to `--replace-quiet` to get a build.
   - Never add `--fuzz`.

4. **Adapt checks and data for `quattro`**, each as its own carry commit:
   - `pkgs/review.sh:300-316`: accept
     `omarchy_pin =~ ^[0-9a-f]{40}$` together with
     `pkg_version =~ ^edge-[0-9]{8}-${omarchy_pin:0:7}$`. Add a case in
     `tests/review-pins.nix` that fails with a mismatched sha7.
   - `tests/panel-loaders.nix:31-43`: the negative control is upstream's own
     bug, which `quattro` fixed. Retarget it so the check still asserts the
     property (no panel `Instantiator`); don't delete it. Say why in the
     commit (§1, read backwards).
   - `data/bin-ledger.nix`, `data/skill-parity.nix`, `data/apps.nix`,
     `data/menu-exceptions.nix`: classify what `quattro` adds or drops, driven
     by each check's own red output.

   **Verify:** build each of `menu-verbs`, `bin-ledger`, `skill-parity`,
   `panel-loaders`, `review-pins` and `stable-eval` separately; all green.
   `options` only when `gh run list` shows nothing in flight.

5. **Make `quattro` boot.**
   - Run `session`, then `coexist` and `plugin`, **only** when nothing is in
     flight in CI (§6 VM tier).
   - Investigate the black desktop from `docs/internals/design.md`'s "What is
     left" item 1: the shell log, missing binaries, Lua `require`s, QML errors.
   - Package only what the session or the gating checks need, each package
     with `meta.mainProgram` and a `data/` row as its neighbours have, as a
     carry commit.
   - Record the cause in `docs/internals/design.md` on `edge` (one paragraph).

   **Verify:** all three boot checks are green on `edge`.

   **Traps:**
   - §5: pin a drvPath and build `"$drv^*"`.
   - §6: kill a wedged VM by pid, never `pkill` by name.

6. **First publish.**
   - Push the seeded `edge` to `refs/heads/edge-candidate`.
   - Run `gh workflow run omarchy-edge.yml`. This only works once PR 1 is
     merged, so `workflow_dispatch` exists on `main`.
   - Confirm `edge` is created by `edge-promote.sh` (first-publish path), not
     by hand.

   **Verify:**
   - `git ls-remote origin refs/heads/edge` equals the candidate.
   - The issue labelled `omarchy-edge` is closed or absent.

### PR 2: switching, reporting, menu, docs (new branch `feat/1278-omarchy-channel-switch`, opened after step 6)

7. **`pkgs/omarchy/nix-bin/nixarchy-channel`: the `omarchy` subcommand and
   `--current`.**
   - Dispatch first on `$1 = omarchy`. Keep every existing nixpkgs path
     byte-for-byte; add `--current` there, printing `stable|unstable|custom`
     from the existing `current` classification.
   - **Classifier**, reading `flake.nix` only:
     - a top-level `omarchy` input whose `url` starts `git+file:`, together
       with the `follows` line inside the `nixarchy = {` block → `dev`;
     - `nixarchy.url` ending `/nixarchy/edge"` → `edge`;
     - `/nixarchy/release"`, or bare `github:olafkfreund/nixarchy"` →
       `stable`;
     - else `custom`.
   - **Switching** reuses the existing helpers: the writable check, the y/N
     prompt, `cp … .pre-channel`, `cksum` before and after, and restore on
     no-op or failed re-lock.
     - Rewrite only `nixarchy.url`, anchored inside the `nixarchy = {` block
       with the awk guard shape at `:202-213`.
     - `dev [PATH]`:
       - PATH defaults to `$HOME/omarchy`; resolve it to absolute.
       - Refuse when PATH has no `.git`, or lacks any of `bin/`, `default/`,
         `shell/`.
       - Refuse when a top-level `omarchy` input already exists and is not
         ours.
       - Warn when `git -C PATH status --porcelain` is non-empty.
       - Insert both lines idempotently.
     - Leaving dev removes both lines.
     - Re-lock `nixarchy`, plus `omarchy` for dev.
     - Print `nh os switch`.
   - `rc` gives a one-line refusal.

   **Check:** extend `tests/channel.nix`.
   - Cases:
     - all six pairings in sequence from the real template fixture
       (`mk` already exists);
     - after each switch, assert both axes' lines, so no rewrite touched the
       other axis;
     - `--current` on both axes;
     - `custom` is refused and the file is unchanged;
     - a dev PATH without `.git` is refused;
     - the backup is restored when the re-lock fails (the sandbox re-lock
       always fails, so assert the restore message and contents);
     - leaving dev removes both lines.
   - Count failures, as the file already does.

   **Red proof:** remove the anchor guard so the rewrite matches every
   `nixarchy`-looking line, and show a pairing case fails. Break `--current`
   and show it fails.

   **Traps:**
   - The template has a commented example line, so anchor matches (see the
     `hm_line` comment at `:96-104`).
   - `set -euo pipefail` plus `grep` with no match → `|| true` where empty is
     legitimate.
   - Run the check under bash, not zsh (§1).

8. **Delegate upstream's channel scripts** (`pkgs/omarchy/default.nix`, beside
   the `omarchy-version-channel` edit at `:728`).
   - Replace the bodies of `share/omarchy/bin/omarchy-channel-current` and
     `omarchy-channel-set` by writing new files with `printf`, not a heredoc
     (§5: nixfmt reindent):
     - `exec nixarchy-channel omarchy --current`;
     - `exec nixarchy-channel omarchy "$@"`.
   - Keep the `# omarchy:summary=` and `# omarchy:args=` header lines; the CLI
     reads them.
   - `data/bin-ledger.nix:175-184`: both entries become `class = "patch"`, and
     `omarchy-channel-set` loses its `pacman` note.

   **Check:**
   - `bin-ledger` passes.
   - `tests/channel.nix` gains: `omarchy-channel-set edge` produces the same
     file as `nixarchy-channel omarchy edge`, and `omarchy-channel-current`
     prints `stable` on the fixture.

   **Red proof:** revert the delegation and show both cases fail.

9. **Menu split** (`modules/apps.nix:635-680`).
   - `update.channel`: description "Which Omarchy you run: stable, edge, or
     your own checkout. Separate from nixpkgs".
   - Children:
     - `stable`: `nixarchy-channel omarchy stable`;
     - `edge`: `nixarchy-channel omarchy edge`;
     - `dev`: `nixarchy-channel omarchy dev`;
     - `rc`: keeps `when = "false"`.

     Each action uses `omarchy-launch-floating-terminal-with-presentation`.
     Each gives a full row (icon, label, action, description): the generator
     blanks omitted keys (`:955-960`).

     Check marks are inherited from upstream (`:961`). Confirm in the generated
     jsonc.
   - New `update.nixpkgs` (label "Nixpkgs") with `stable` and `unstable`,
     moved from today's rows, plus explicit
     `checked = "[[ \"$(nixarchy-channel --current)\" == stable ]]"` (and
     `== unstable`).
   - Rewrite the `#529` comment block above to describe the two groups.

   **Check:** `tests/menu-verbs.nix`.
   - Add `scan '\bnixarchy-channel +omarchy +[-a-z]+' 3 …` against a verbs
     list from the `omarchy` case.
   - Assert from the generated `omarchy-menu.jsonc` (`jq`) that:
     - `update.channel.{stable,edge,dev}` actions contain
       `nixarchy-channel omarchy`;
     - `update.nixpkgs.{stable,unstable}` actions contain
       `nixarchy-channel stable|unstable`;
     - all five have a non-empty `checked`.

   **Red proof:** point `update.channel.edge` back at `nixarchy-channel
   unstable` and show it fails.

   **Traps:**
   - `menu-verbs`' `verbs_of` reads `case "$target"`. The subcommand's case
     must be readable by it, or extend `verbs_of`.
   - Don't break the existing nixpkgs scan lines (`:196-197`).

10. **Reporting.**
    - `pkgs/doctor.sh` (after the nixpkgs block, `:661-708`): an
      `omarchy-channel` line from `nixarchy-channel omarchy --current`:
      - `ok` for stable or edge;
      - `info` for dev, naming the path;
      - `warn` for custom.

      No second parser.
    - `pkgs/omarchy/nix-bin/nixarchy-version`: append ` (edge)` or ` (dev)`
      when not stable.

    **Check:** the doctor's own test (find it with
    `grep -rln doctor tests/`). Add fixture cases for the three channels.
    **Red proof:** drop the line and show the case fails.

11. **`omarchy-update` on dev**
    (`pkgs/omarchy/nix-bin/omarchy-update:210-217`). When the target is
    `nixarchy` and `nixarchy-channel omarchy --current` is `dev`, set
    `update_flags=(--update-input nixarchy --update-input omarchy)`. First
    confirm that nh 4.4.2 accepts the flag twice (`nh os switch --help`). If it
    does not, run `nix flake update omarchy --flake "$flake"` first and say so.
    Update the `dim` text to mention the checkout.

    **Check:** the existing `omarchy-update` test, if one exists
    (`grep -rln omarchy-update tests/`). Otherwise add a stubbed-`nh` case to
    `tests/channel.nix` that records its arguments. **Red proof:** revert and
    show the case fails.

12. **Prove the dev override works (one-time evidence, recorded in the PR; not
    a CI check).** A sandbox cannot fetch the real inputs.
    - On p620, make a scratch copy of an installed-style flake: the real
      template filled with the PR 2 branch as `nixarchy.url`.
    - Run `nixarchy-channel omarchy dev /mnt/data/vmtest/omarchy-checkout`,
      then evaluate that all three are the checkout's store path:
      - `nixarchy.inputs.omarchy.outPath`;
      - nixi's Omarchy input;
      - nixarchy-menu's Omarchy input.
    - Remove the `follows` line and show the assertion fails.

    Paste both outputs in the PR. This settles the spec's open risk about
    `follows` onto a `flake = false` input.

13. **Docs.**
    - `docs/manual/channels.md`: a "Two choices: nixpkgs and Omarchy" section
      covering:
      - the six pairings;
      - the commands;
      - the dev loop (commit in the checkout, then `omarchy-update --nixarchy`);
      - that uncommitted edits are not built;
      - rollback (`nixarchy-channel omarchy stable`, or the previous
        generation).
    - `docs/manual/updates.md` links to it.
    - Check `docs/AGENTS.md` for the manual's three lists. This edits existing
      pages, so none should change. Confirm.

    **Check:** the docs build and link check the repo already runs; read
    `docs/AGENTS.md` for the command. `readme-counts.sh` if it counts menu rows
    or commands.

## Tests

| Command | Expected |
|---|---|
| `nix build .#checks.x86_64-linux.edge-promote` | green; red with the ancestor test or the head test removed |
| `nix build .#checks.x86_64-linux.channel` | green; red with the anchor guard or the delegation removed |
| `nix build .#checks.x86_64-linux.menu-verbs` | green; red with a channel row pointed back at nixpkgs |
| `nix build .#checks.x86_64-linux.bin-ledger` | green with the two entries as `patch` |
| `nix build .#checks.x86_64-linux.review-pins` (on `edge`) | green; red with a mismatched sha7 |
| `actionlint` on the two workflows | clean |
| `nix fmt -- --ci`, `statix check .`, `deadnix --fail .` | clean before every push |
| `omarchy-edge.yml` first publish | `edge` created by the script, gates green |

Cheap checks run one at a time under `flock /mnt/data/vmtest/codex-build.lock`.
`options` and the VM checks run only when `gh run list` shows nothing in flight
(§6).

## Model split

Steps 1–2 and 7–11 edit files across three or more steps, so they go to the
`coder` agent:

- one agent for PR 1 (steps 1–2);
- one for PR 2 (steps 7–11), each later step sent with `SendMessage`.

Steps 3–6 (seeding `edge`) and steps 12–13 stay with the lead. They are
investigation and evidence, not plan-following edits. Each PR is reviewed by a
fresh Opus agent given only this plan and the `git diff`.

## Rollback

- **PR 1:** revert the merge. Delete `edge-candidate`. `edge` stays where it
  is; nobody follows it until PR 2 ships.
- **Edge content:** stop the workflow (`gh workflow disable omarchy-edge.yml`).
  `edge` stays at its last green commit, so users on it keep a working pin.
- **PR 2:** revert the merge. A user on edge or dev keeps working (their flake
  names a branch that still exists), and `nixarchy-channel omarchy stable`
  still exists on their current generation. The manual's rollback section
  says how to edit the one line back by hand.
- **Per machine:** `nixarchy-channel omarchy stable`, or restore
  `flake.nix.pre-channel`, or boot the previous generation.

## Deviations recorded during implementation

- **Step 1.** The refusal cases assert the script's own reason on stderr, not
  only its exit status. git's plain push already refuses a non-fast-forward,
  so without that the ancestor test's red proof stayed green. The ancestor
  test is kept for its message.
- **Step 2:**
  - **The briefings.** They go to the step summary and step outputs. The
    rolling issue carries a one-line `edge-sig:` and the run link, because
    the briefings can be large.
  - **The label.** `report` runs `gh label create omarchy-edge --force`, as
    `weekly.yml` already does for its own label. It no longer asks the owner
    to create it by hand.
  - **The self-hosted `verify` job.** Its runner shell has no `gh` or `git`,
    so it takes both from `nix run`/`nix shell --inputs-from .`.
    `actions: read` is added for `gh run list`.
  - **A cancelled job.** `report` treats one as a failure, since a timeout
    reports as cancelled.
  - **Checkouts.** Both use `secrets.NIXARCHY_EDGE_TOKEN || github.token`.
    `GITHUB_TOKEN` cannot push commits that change `.github/workflows`, and
    merging `main` into edge carries those. The PR asks the owner for that
    secret: a token with the workflows scope.
