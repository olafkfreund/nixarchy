---
status: draft
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
   That is a CI-gate change, merged by a maintainer, and only after the edge
   carry is green.
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
- Build `checks.x86_64-linux.menu-actions` under
  `flock /mnt/data/vmtest/codex-build.lock`. Save the `menu-actions:` lines to
  `/mnt/data/vmtest/1325-before.txt`.
- **Compare with the spec's 31.** `edge-candidate` has moved to quattro
  386176a since the spec. If any finding is new or gone, stop. Classify the
  difference the way the spec did, and add it to this plan before step 1.
- Find what `install.style.theme` and `remove.preinstalls` reach on edge. Run
  the walker on those two rows (the `walk()` function at
  `check-menu-actions.py:66-81`, against the built edge tree), and record
  their hazard and first script here. Step 1's rewording depends on it.

Traps:
- §5: a flake sees only tracked files, so `git add` before building.
- §5: `git merge-base` and `git show --stat` after the merge.

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

Then green again. `bin-ledger` and `menu-guards` must be green on edge too.

Traps:
- §5: `git checkout HEAD --`, not `git checkout --`.
- §1: a break that stays green may never have applied.

### 3. [lead] Commit, push and dispatch the edge carry

- Squash to one commit: `Edge: menu-actions classifies quattro's new rows and drops three that no longer exist (#1325)`.
- Check the install queue is 0, then push `HEAD:edge-candidate`. That is a
  fast-forward; never a force-push.
- `gh workflow run omarchy-edge.yml --ref main -f from_candidate=true`. In the
  run, read that `edge-candidate` keeps the commit.

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

- `menu-actions` on main stays green, with 335 rows and 48 flagged.
- `nix fmt -- --ci`.
- Squash to one commit: `Edge's CI runs menu-actions, and tests/AGENTS.md names the walker's blind spots (#1325)`.
- The PR body:
  - links the intent, spec and plan;
  - says it changes a CI gate, for a maintainer to merge **after** the edge
    run on the carry is green;
  - includes the B1–B3 output;
  - says `Refs #1325`.
- Close #1325 by hand once both are in, naming the edge commit and the PR
  (§12).

## Tests

| command | expect |
|---|---|
| `menu-actions` on the edge tree | green |
| `menu-actions` on main | green, 335 rows, 48 flagged |
| B1–B3 | each red with its message, then green |
| `bin-ledger`, `menu-guards` on edge | green |
| `actionlint` on `omarchy-edge.yml` | clean |
| edge run on the carry | the build step lists `menu-actions` green, once the workflow PR is in |

## Rollback

- **Edge:** revert the `Edge:` commit on `edge-candidate`. The next edge run
  carries the revert.
- **Main:** revert the PR. That removes `menu-actions` from edge CI and the
  note.
- Nothing is stateful.
