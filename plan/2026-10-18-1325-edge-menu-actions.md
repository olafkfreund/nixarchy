---
status: approved
issue: 1325
spec: spec/2026-10-18-1325-edge-menu-actions.md
---

# Plan: checks.menu-actions passes on edge, and each of its findings there is a decision rather than noise

## Approved decisions, carried over

1. **No finding is a dangerous row.** 22 are walker artefacts, 8 are real and
   harmless, and 3 are stale. The spec's table holds the evidence for each.
2. **Classify on `edge-candidate` only.** `data/menu-actions.nix` is shared,
   and its stale rule (`check-menu-actions.py:131-132`) fires for a row that
   does not exist. Entries for edge-only rows on main would turn stable red.
3. **The walker does not change.** Its blind spots get a note in
   `tests/AGENTS.md` on main.
4. **`menu-actions` joins the edge cheap-check list** in `omarchy-edge.yml`.
   That is a CI-gate change, merged by a maintainer, and only once `edge`
   itself contains the carry:
   `git merge-base --is-ancestor <carry> origin/edge`.
   `edge-candidate` alone is not enough. It is a scratch ref: a run that is
   not `from_candidate` starts from `edge` and force-pushes it
   (`omarchy-edge.yml:99-102`, `:348`). The 06:00 scheduled run does exactly
   that, and `cancel-in-progress` (`:37-39`) lets it cancel a dispatched run
   still waiting in `wait-idle`.
5. **Remove › SSH Agent keeps its upstream script,** with a `session:` reason.
   Its NixOS wording is left as is.
6. **Closing:** the main PR is `Refs #1325`. #1325 closes by hand once the
   edge carry is green and the workflow PR has merged, listing both.

## Who does what

The coder (Sonnet) does steps 1, 4 and 5, one `SendMessage` per step. The
lead does 0, 2, 3 and 6, plus every commit and push.

## Steps

### 0. [lead] Edge worktree, and re-measure the findings

- `git worktree add -b edge-carry-1325 /mnt/data/vmtest/wt-1325-edge origin/edge-candidate`,
  then `git merge origin/main`. Read the merge status, and resolve any
  conflict the way earlier `Edge:` carries did.
- **Wait for any edge run in flight to finish** first. Run 39076339015
  promotes #1313's carry, and a new dispatch would cancel it. Proceed when
  `origin/edge` contains `origin/edge-candidate`, or the run has ended.
- Build `checks.x86_64-linux.menu-actions` under
  `flock /mnt/data/vmtest/codex-build.lock`. Save the `menu-actions:` lines to
  `/mnt/data/vmtest/1325-before.txt`.
- **Compare with the spec's 31.** `edge-candidate` has moved to quattro
  386176a since the spec. If any finding is new or gone, stop. Classify the
  difference the way the spec did, and add it to this plan before step 1.
- Find what `install.style.theme` and `remove.preinstalls` reach on the
  **merged** tree with the script's `--measure` flag (`check-menu-actions.py:45,106`),
  and record their hazard and first script here. Step 1's rewording depends on
  it. Before the merge, both read `omarchy-install-hermes-cli: systemctl-user`
  and `remove.preinstalls` no longer reached `home-rm`; #1319 touched it.
- Also build `menu-verbs`, `bin-ledger` and `menu-guards` on the merged tree.
  main's #1307 added reachability checks that edge's cheap list runs. If one
  is red because of quattro, report it as unrelated (§10) and do not fix it
  here.

Traps:
- §5: a flake sees only tracked files, so `git add` before building.
- §5: `git merge-base` and `git show --stat` after the merge.

### Step 0 results (2026-10-18)

- Edge tree: `edge-candidate` (quattro 386176a) merged with main 4ff4e62e,
  merge commit 21b22fb6, clean.
- `menu-actions`: the same 31 findings as the spec, none new, none gone
  (`/mnt/data/vmtest/1325-before.txt`).
- `--measure`: `install.style.theme` and `remove.preinstalls` both reach only
  `omarchy-install-hermes-cli: systemctl-user`. That stop is on its `--now`
  branch (line 542). `install.style.theme` reaches it through
  `omarchy-theme-set-hermes`, which runs `--check` only. `remove.preinstalls`
  runs `--owns`, which quattro's script no longer accepts: it falls to the
  usage branch and exits 1. Neither reaches `home-rm` any more, so `owned:`
  no longer fits; both become `unreached:`.
- `menu-verbs` is red on quattro for #1329 (`apps.*`, `remove.dictation.*`),
  unrelated here (§10). `bin-ledger` and `menu-guards` are green.

### 1. [coder] `data/menu-actions.nix` in `wt-1325-edge`

Keep the file's key order and its nixfmt wrapping.

- **Add** these entries, with these reasons:
  - `setup.default.browser.{brave,brave-origin,chrome,chromium,edge,firefox,zen}`
    and `update.password.drive`:
    `"unreached: pacman is omarchy-lifecycle-dispatch reading /var/lib/pacman/local, which x86_64 never reaches (exit 0 first)"`;
  - `setup.default.editor.{cursor,emacs,helix,neovim,sublime,vim,vscode,zed}`:
    `"unreached: theme-set-hermes runs omarchy-install-hermes-cli --check only; its user-unit stop is the --now branch"`;
  - `style.font.cjk.{auto,hk,jp,kr,sc,tc}`: `"session: restarts the user's shell unit"`;
  - `setup.default.agent.{agy,kimi,ori}`:
    `"session: the OpenClaw branch starts a user unit; other agents never take it"`;
  - `setup.security.fingerprint`: `"guidance: exits 1 before omarchy-apply-lock"`;
  - `setup.security.ssh-agent`: `"session: enables the user's gcr-ssh-agent socket"`;
  - `remove.service.ssh-agent`:
    `"session: disables the user's gcr-ssh-agent socket and removes its own environment.d file"`.
- **Remove** `style.theme`, `setup.default.agent.gemini` and
  `setup.default.agent.antigravity`.
- **Reword** `install.style.theme` and `remove.preinstalls` to match what step
  0 recorded. Keep each reason's first class word, unless step 0 shows it no
  longer fits.

Verify: `nix fmt`, then `menu-actions` on the edge tree is green.

Traps:
- An editor or agent hook may reformat `.nix` files with `nixpkgs-fmt`. Run
  `nix fmt` and read `git diff --stat` (§5).

### 2. [lead] §1 breaks on the edge tree

Commit step 1 as a temporary `wip:` commit first, so there is a baseline to
check out of. For each break:
1. apply it;
2. prove it landed with `git diff`;
3. `git add -A`, build, and capture the output;
4. restore with `git checkout HEAD -- data`.

| break | expect |
|---|---|
| B1: delete the `setup.default.browser.firefox` entry | `setup.default.browser.firefox reaches omarchy-lifecycle-dispatch: pacman, with no entry` |
| B2: delete the six `style.font.cjk.*` entries | six `style.font.cjk.* reaches omarchy-restart-shell` lines |
| B3: restore `style.theme`'s old entry | `entry for style.theme, which reaches no hazard: stale` |

Then green again. `menu-verbs`, `bin-ledger` and `menu-guards` must be no
redder than step 0 measured.

Traps:
- §5: `git checkout HEAD --`, not `git checkout --`.
- §1: a break that stays green may never have applied.

### 3. [lead] Commit, push and dispatch the edge carry

- Squash with `git reset --soft <step 0's merge commit>`, not against
  `origin/edge-candidate`. Against `origin/edge-candidate` it would fold main's
  new commits into the carry (§5). Subject:
  `Edge: menu-actions classifies quattro's new rows and drops three that no longer exist (#1325)`.
  Check that `git show --stat HEAD` lists only `data/menu-actions.nix`, and
  that `git merge-base origin/main HEAD` equals `origin/main`.
- No edge run in flight, and the install queue at 0. Then push
  `HEAD:edge-candidate`, which must be a fast-forward; never force it. If
  it is rejected, fetch, merge the new `origin/edge-candidate`, re-run
  `menu-actions`, and push again.
- `gh workflow run omarchy-edge.yml --ref main -f from_candidate=true`. Do this
  well before 06:00 UTC, so the scheduled run cannot cancel it.
- **Done** when `git merge-base --is-ancestor <carry> origin/edge` succeeds. If
  the run fails, or is cancelled, the next scheduled run drops the carry. Push
  it again and dispatch again.

### Deviation in step 3 (2026-10-18)

The carry (22115c78, on `edge-carry-1325`) is committed but not pushed.
Edge's `menu-verbs` is red for #1329, so a dispatched run would fail in
`prepare`, and the next scheduled run starts from `edge` and drops the carry.
It is pushed with #1329's edge merge, and done still means `edge` contains it.

### 4. [coder] `tests/AGENTS.md`, main worktree `wt-1325`

In "menu-actions proves classification, not safety (#1304)", the paragraph
"It cannot see `nixarchy-*` commands …" gains two sentences:
- The walker follows every `omarchy-*` name in a script, whichever `case`
  branch it sits in and even inside `echo` text. So a dispatch script flags
  every row that calls it, and the reason names the branch.
- It does not follow `"$OMARCHY_PATH/bin/omarchy-x"`.

Then add one sentence: edge entries live only on `edge-candidate`, because the
stale rule fires for a row the channel does not have (#1325).

### 5. [coder] `.github/workflows/omarchy-edge.yml:239`, main worktree

Add `menu-actions` to
`for c in menu-verbs bin-ledger skill-parity panel-loaders review-pins stable-eval; do`.

Verify: `nix run nixpkgs#actionlint -- .github/workflows/omarchy-edge.yml`.

### 6. [lead] Main PR

- `menu-actions` on main stays green. The PR touches no data, so the counts
  are main's own.
- `nix fmt -- --ci`.
- Squash to one commit: `Edge's CI runs menu-actions, and tests/AGENTS.md names the walker's blind spots (#1325)`.
- The PR body:
  - links the intent, spec and plan;
  - says it changes a CI gate, for a maintainer to merge **after** the edge
    run on the carry is green;
  - includes the B1–B3 output;
  - says `Refs #1325`.
- Close #1325 by hand once `edge` contains the carry and the PR has merged,
  naming both (§12).

## Tests

| command | expect |
|---|---|
| `menu-actions` on the edge tree | green |
| `menu-actions` on main | green |
| B1–B3 | each red with its message, then green |
| `bin-ledger`, `menu-guards` on edge | green |
| `actionlint` on `omarchy-edge.yml` | clean |
| edge run on the carry | the build step lists `menu-actions` green, once the workflow PR is in |

## Rollback

- **Edge:** revert the `Edge:` commit on a branch from `edge`. Push it to
  `edge-candidate` and dispatch with `from_candidate=true`; a scheduled run
  starts from `edge` and would not carry the revert.
- **Main:** revert the PR. That removes `menu-actions` from edge CI and the
  note.
- Nothing is stateful.
