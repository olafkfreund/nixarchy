---
status: draft
issue: 1718
spec: spec/2026-11-09-1718-install-phase-budget.md
coders:
  1: coder  # deleting named comment lines; exact ranges below, nothing to decide
  2: coder  # moving two blocks to pkgs/AGENTS.md with anchors; mechanical, but agy cannot reach /mnt/data worktrees (measured on #1705)
reviewers:
  - codex  # line by line against this plan
  - agy    # an independent read of the diff
---

# Plan: the omarchy install phase fits its budget on both pins

## Decisions carried from the approved intent and spec

- **Target.** `checks.install-phase-budget` must pass with at least 3,000
  bytes below the 123,000 budget on edge's merged tree: at most 120,000
  bytes there, against 123,181 measured on 2026-11-09.
- **Scope.** Only comment lines in `pkgs/omarchy/default.nix`'s
  `installPhase` change, plus text in `pkgs/AGENTS.md`. No shell line, no
  `--replace-fail` text, and no indentation of the remaining lines moves.
- **Order.** First delete what is dead or already written down, then move
  whole blocks.
- **Line numbers** below are on `main` at `3c56f888`. After step 1 they
  shift, so step 2 finds its blocks by their first line's text.

### Deletions (step 1)

| lines | what | in its place |
|---|---|---|
| `445-450` | the #1153 "CARRIED, for #1153" comment | nothing. Keep one blank line between the `find … -delete` line (`:443`) and what follows |
| `452-453` | the #1155 "CARRIED (#1155)" comment | nothing. The `# CARRIED (#1192)` line and its `patch` line stay |
| `586-594` | the `chromium.desktop` fallback explanation ("Both launchers accept…" to "…needed nothing beyond the path fix below.") | one line, `# Why: pkgs/AGENTS.md#every-web-app-failed-with`, at the indent the deleted block had |
| `959-962` | the `#` and `# Short version:` lines under the browser-policy pointer | nothing. The pointer at `:958` stays |
| `1085-1089` | the `#` and `# Short version:` lines under the agent-skills pointer | nothing. The pointer at `:1084` stays |
| `1093` | `# is absent -- is the one this loop exists to prevent.` | nothing in the phase; step 2 adds it to `pkgs/AGENTS.md` |

### Moves (step 2)

Each block moves whole to `pkgs/AGENTS.md`, under an explicit
`<a id="…"></a>` and a `##` heading, placed beside the related sections. At
the code, one line stays: `# Why: pkgs/AGENTS.md#<anchor>`, at the block's
indent.

| first line in `default.nix` | lines on `main` | anchor | heading |
|---|---|---|---|
| `# Every unit in default/systemd/user has ExecStart=/usr/bin/..., and one` | `786-800` | `speaker-tuning-execstart` | Speaker tuning's unit names `/run/current-system/sw` |
| `# 1Password'"'"'s Chromium extension, installed the way NixOS installs one.` | `906-923` | `onepassword-extension-dir` | 1Password's Chromium extension is a NixOS option |

- The 1Password text gets a plain apostrophe in `pkgs/AGENTS.md`.
- The heading text is new. The body is the comment, unwrapped from `#` and
  otherwise unchanged.
- **Fallback, only if step 3 measures more than 120,000 on edge's merged
  tree:** move the block that starts `# The same wordmark on the boot
  splash.` (`:1607`) the same way, with anchor `boot-splash-wordmark`.
  Record it as a deviation in this plan.

### `pkgs/AGENTS.md` edits (step 2)

- `## Video and GIF desktop backgrounds, backported onto v4.0.4 (#1153)`
  (`:983`) and `## Panel loaders survive a plugin change (#1155)` (`:915`)
  each get, as the first line under the heading:
  `**Retired 2026-10-21** with the move to Omarchy v4.5 (#1405, 2cd3c23), which carries both upstream. What follows is history.`
  This is the form #953's section uses at `:171`.
- `#default-agent-menu-commands-use-the-id` ends mid-sentence ("The
  direction that would matter -- ticking for an agent that"). Append "is
  absent -- is the one this loop exists to prevent." so it reads whole.
- In `## Why the install phase says so little` (`:652`), delete the two
  sentences that begin "The figure moves by 12 bytes with git state":
  `nixarchyRev` no longer exists.

## Steps

1. **`pkgs/omarchy/default.nix`**: the deletions (coder).
   - Verify: `nix fmt`, then `git diff --stat` (only this file), then the
     shell-unchanged comparison below.
   - Traps: never delete a `# Why:` line (`:941`, `:958`, `:1084` and
     `:1092` stay); delete whole lines only, never part of one; a hook on
     this machine may reformat `.nix` with `nixpkgs-fmt`, which `nix fmt`
     reverts (CLAUDE.md §5).
2. **`pkgs/omarchy/default.nix` and `pkgs/AGENTS.md`**: the moves and the
   `pkgs/AGENTS.md` edits (coder).
   - Verify: the same comparison; and for each new
     `# Why: pkgs/AGENTS.md#X`, `grep -c '<a id="X">' pkgs/AGENTS.md`
     prints 1.
   - Traps: keep each block's wording; only the leading `# ` goes.
3. **Measure, run, break, commit, PR** (session).
   - **Shell unchanged.** Evaluate `.#omarchy.installPhase` on `3c56f888`
     and on the branch head, both committed. Then, for each:
     `sed -E 's#/nix/store/[a-z0-9]{32}-#STORE-#g' | grep -Ev '^[[:space:]]*(#|$)'`.
     `diff` the two results; the diff must be empty.
     - §1 break: change one character of one shell line in the branch copy
       of the output and show a non-empty diff.
   - **Budget on main.** `checks.install-phase-budget` passes and reports
     at least 3,000 bytes before it fails.
   - **Budget on edge.** Make a detached worktree of `origin/edge-candidate`
     and merge the branch into it. Then `nix eval --raw
     .#omarchy.installPhase | wc -c` must print at most 120,000, and
     `checks.install-phase-budget` must pass there.
     - The §1 proof is the same check on `main`'s tree, which fails
       (runs 42544068473 and 42571154200).
   - **Package tier**, when both `vm-host-free.sh install` and `edge` print
     `free`: `nix build .#omarchy`.
   - **Cheap tier:** `nix fmt -- --ci`, statix, deadnix, `patched-files`,
     `bin-ledger`, `grep-q-pipefail`.
   - One commit per step. The PR says `Closes #1718`, links the three
     artifacts, and gives the before and after byte counts on both trees.
     Then "@codex review". Merge commit.

## Tests

| check | tier | expect |
|---|---|---|
| shell-unchanged comparison | eval | empty diff; the one-character break is non-empty |
| `install-phase-budget` on the branch | cheap | passes, at least 3,000 bytes to spare |
| `install-phase-budget` on edge's merged tree | cheap | passes, at most 120,000 bytes |
| `omarchy` | package | builds |
| `patched-files`, `bin-ledger`, `grep-q-pipefail` | cheap | pass |

## Rollback

Revert the PR. The comments come back, and edge goes red at the budget
again.
