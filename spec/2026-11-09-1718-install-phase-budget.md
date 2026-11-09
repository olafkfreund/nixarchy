---
status: approved
issue: 1718
intent: intent/2026-11-09-1718-install-phase-budget.md
---

# Spec: the omarchy install phase fits its budget on both pins

## Design

The change touches only comment lines in `pkgs/omarchy/default.nix`'s
`installPhase`, and adds text to `pkgs/AGENTS.md`.

- **Target** (approved intent): `checks.install-phase-budget` passes with
  at least 3,000 bytes below the 123,000 budget, measured on edge's merged
  tree. Edge measured 123,181 bytes on 2026-11-09, so the phase must lose at
  least 3,181 bytes. `main` (122,676) then sits about 3,500 under the
  budget.
- **Order** (approved intent): first delete what is dead or already
  written down; then move whole blocks.

### 1. Delete: dead, or already in `pkgs/AGENTS.md`

Line numbers are on `main` at `3c56f888`.

| lines | what | why it can go |
|---|---|---|
| `445-450` | the #1153 "CARRIED … backported onto v4.0.4" comment | the patch and its `patch` line are gone (`ls pkgs/omarchy/*1153*` finds nothing); `pkgs/AGENTS.md#video-and-gif-desktop-backgrounds…` keeps the history |
| `452-453` | the #1155 "upstream's per-entry panel sync" comment | same: no #1155 patch remains, and `pkgs/AGENTS.md` "Panel loaders survive a plugin change (#1155)" holds it |
| `586-594` | the `chromium.desktop` fallback explanation | `pkgs/AGENTS.md#every-web-app-failed-with` says the same. Replace it with that anchor's `# Why:` line, as `:941` already does |
| `959-962` | the `# Short version:` under the browser-theme-policy pointer | the pointer above it stays; the anchor holds the long version |
| `1085-1089` | the `# Short version:` under the agent-skills pointer | same |
| `1093` | `# is absent -- is the one this loop exists to prevent.` | the second half of a sentence whose first half is already in `pkgs/AGENTS.md#default-agent-menu-commands-use-the-id`. It moves there to finish the sentence |

### 2. Move: the two largest remaining blocks

Each one goes whole under a new `pkgs/AGENTS.md` heading with an explicit
`<a id>` anchor, and a one-line `# Why: pkgs/AGENTS.md#<anchor>` stays at
the code (CLAUDE.md §7).

| lines | block | bytes in the phase | anchor |
|---|---|---|---|
| `786-800` | speaker tuning's `ExecStart=/usr/bin/pipewire` and why `/run/current-system/sw` | 1,169 | `speaker-tuning-execstart` |
| `906-923` | 1Password's Chromium extension, and why `echo` lines replaced a heredoc | 1,182 | `onepassword-extension-dir` |

- The 1Password block is an ordinary phase comment (every quote before it
  balances; checked 2026-11-09), but its first line spells the apostrophe
  `'"'"'`, a leftover of quoting. In `pkgs/AGENTS.md` it becomes a plain
  apostrophe.
- If sections 1 and 2 together do not reach 3,181 bytes on edge's merged
  tree, the next-largest block moves the same way: the boot-splash wordmark
  comment that starts at `1607` ("The same wordmark on the boot splash",
  944 bytes). The plan records which blocks were needed.

### 2a. The history sections say the patches are gone

Deleting the #1153 and #1155 comments would leave `pkgs/AGENTS.md`
describing both patches as live: "applied FIRST" at `:936` and `:994`.
Neither patch file nor its `patch` line exists. Each section gets a
**Retired** line at its top, in the form #953's section already uses: the
release that dropped the patch, and that what follows is history. The plan
finds that release with `git log -S` on the patch file name.

### 3. Nothing else changes

- No shell line, no `--replace-fail` text, and no indentation of the
  remaining lines changes.
- If a deleted or moved comment held the phase's minimum indent, every
  line would be reindented (`pkgs/AGENTS.md`, "A long build phase is one
  indented string"). The comparison below catches that.
- The budget number, the check, and `__structuredAttrs` stay as they are
  (intent constraints).

## Alternatives rejected

- **Raising the budget.** It silences the warning and leaves the
  `execve` ceiling where it is.
- **`__structuredAttrs` for omarchy.** It removes the limit, but the check
  itself calls it a larger change, and it was ruled out of scope.
- **Moving many small blocks.** Each move leaves a `# Why:` line that still
  costs bytes. A few large blocks save the most per pointer.
- **Fixing it on edge only.** Edge merges `main` each run, so a fix there
  would be overwritten. And `main` is 324 bytes from failing too.

## Risks

- **A pointer to an anchor that does not exist** reads as documentation and
  leads nowhere. Every new `# Why:` names an explicit `<a id>` that this
  change adds, and the verification greps for each one.
- **`nix fmt` reflows the phase.** Deleting lines from an indented string
  can change what nixfmt does (CLAUDE.md §5). Run `nix fmt`, then read
  `git diff --stat`: only `pkgs/omarchy/default.nix` and `pkgs/AGENTS.md`
  should change, by about the lines named here.
- **A stale sentence in `pkgs/AGENTS.md`.** "Why the install phase says so
  little" says the figure moves by 12 bytes with git state because
  `nixarchyRev` is spliced in twice. `nixarchyRev` no longer appears in
  `pkgs/omarchy/default.nix` or `flake.nix` (agy review, checked
  2026-11-09), so that sentence is deleted in the same edit.

## Verification

1. **Shell unchanged.** Evaluate `.#omarchy.installPhase` on `main`
   (`3c56f888`) and on the branch, both committed. Normalise:
   - every store path hash (`/nix/store/<32 chars>-` to `STORE-`). The
     phase interpolates repository files such as
     `${./1192-panel-loader-errorstring.patch}` (`:455`) and
     `${./nixarchy-logo.py}` (`:1604`), whose store paths move with every
     commit (Codex review);
   Then drop comment lines and blank lines
   (`grep -Ev '^[[:space:]]*(#|$)'`), keeping every remaining line's leading
   spaces so a reindent shows, and diff. The diff must be empty.
   - §1 break: change one character of one shell line in the branch copy,
     re-run, and show a non-empty diff. Then restore it.
2. **Budget.** `checks.install-phase-budget` passes on the branch, and its
   output shows at least 3,000 bytes before it fails.
3. **On edge's merged tree.** Merge the branch into a detached
   `origin/edge-candidate` worktree and evaluate
   `builtins.stringLength omarchy.installPhase`. It must be at most 120,000.
   Run the check there too.
   - §1 break: on `main` as it is, the same check fails on edge's merged
     tree (runs 42544068473 and 42571154200 already show it failing).
4. **Anchors.** For every `# Why: pkgs/AGENTS.md#X` this change adds, `grep`
   finds `<a id="X">` or a heading that GitHub would slug to `X`.
5. **The package builds**: `nix build .#omarchy` on the package-tier gate.
   Run the cheap tier as well: `nix fmt -- --ci`, statix, deadnix,
   `patched-files`, `bin-ledger`, `grep-q-pipefail`.
6. **After merge**, edge's next run passes `prepare` and publishes, and
   #1718 closes.
