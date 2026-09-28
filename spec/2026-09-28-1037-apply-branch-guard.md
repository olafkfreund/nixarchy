---
status: draft
issue: 1037
intent: intent/2026-09-28-1037-apply-branch-guard.md
---

# Spec: rebuilding from the flake checkout refuses a branch nobody chose to deploy

## The open questions, settled

1. **The override is `ALLOW_BRANCH_DEPLOY=1`, the same name nixos_config's
   #2056 uses.** It is a separate variable, not `apply --yes`: `--yes` means
   "don't ask me to confirm the switch", and every scripted
   `apply --detach --yes` (the rebuild panel runs exactly that) would
   otherwise walk straight past the guard. Using the *same* name as
   nixos_config means one habit works for both tools, on a machine where
   both guard the same checkout. It isn't `NIXARCHY_`-prefixed; that's the
   cost, and consistency with the tool already guarding this checkout
   outweighs it. *Push back here if you want the prefix.*
2. **"The default branch" is resolved offline, from local refs only:**
   - `refs/remotes/origin/HEAD`, if set, names the default branch (for
     example `origin/main` gives `main`).
   - Otherwise it's `main`.
   - **On the default branch** means the current branch is that name, or
     HEAD is detached **at exactly** `refs/remotes/origin/<default>`. This
     matches #2056 ("a worktree detached exactly at origin/main is main"),
     so for the owner's checkout both tools give the same answer.
   - **No remote at all:** proceed. A checkout with no remote has no
     "somebody else's branch" to protect against, and it is the layout
     `nixos-generate-config` users start with.
   - **Not a git checkout,** or a flake reference that isn't a local
     directory (`github:…`, `path:` elsewhere): proceed, as today.

## Design

### One helper: `nixarchy-branch-guard <flake>`

A `writeShellApplication` (`git` and `coreutils` in `runtimeInputs`):

- Strips a `#attr` suffix and resolves the directory. If it isn't a local
  directory, or `git rev-parse` says it isn't a work tree, exit 0.
- **Every git call is read-only and passes `-c safe.directory=<dir>`.** The
  checkout and the process reading it are often different users. On an
  installed machine `/etc/nixos` belongs to the user (`installer/install.sh`
  chowns it; `installer/cd.nix:840`), and **`autoUpdate` runs as root**. A
  hand-made `/etc/nixos` is root-owned, and `apply` runs as the user. Either
  way `git` refuses another user's repository ("detected dubious
  ownership"), and the guard would error on exactly the machines it exists
  for. It is scoped to the one directory and to reads; nothing is written.
- Exit 0 when on the default branch (rules above) or when
  `ALLOW_BRANCH_DEPLOY=1`.
- Otherwise exit 1, having printed, following #2056:

      nixarchy: refusing to rebuild from 'feature/x' (a1b2c3d), not main.
        /etc/nixos is the flake this machine builds; building a branch
        deploys it.
        switch back:      git -C /etc/nixos switch main
        build it anyway:  ALLOW_BRANCH_DEPLOY=1 <the command you ran>

One definition, so the three callers cannot disagree (the intent's
constraint).

### The three callers

1. **`nixarchy-apply`** calls the guard right after `flake=` is resolved
   (`modules/apps.nix:3398`), **before** it writes the selection into the
   flake or runs `git add`, so a refusal leaves the checkout untouched.
   **Except in the `--detach` parent**, which skips it. The rebuild panel's
   `startProcess` (`pkgs/rebuild-panel/RebuildState.qml:118`) captures no
   output and ignores the exit code; it polls the unit afterwards. A refusal
   in the parent would start no unit, and the click would silently do
   nothing, which is #1033's defect again. So the refusal happens in the
   child, inside `nixarchy-rebuild`. The unit fails, and the panel already
   shows a failed unit and its journal (#979). The detach block forwards
   `ALLOW_BRANCH_DEPLOY` with `--setenv`, or the child would refuse even
   when the override is set.
2. **`omarchy-update`** calls it before `nh os switch --update`
   (`pkgs/omarchy/nix-bin/omarchy-update:227`). It runs in a terminal, where
   the message is read. Its PATH gets the helper through Omarchy's runtime
   list (`pkgs/omarchy/default.nix`), like every other command the nix-bin
   scripts use.
3. **`autoUpdate`** calls it after the dirty-tree check and before
   `nix flake update nixpkgs`, by store path. So a refused run **doesn't
   touch the lock either**: updating the lock on someone's feature branch is
   its own small intrusion. A refusal fails the unit, and the module's
   existing failure path makes it loud, the same as a dirty tree does.

`omarchy-default-agent` `exec`s `nixarchy-apply` and needs nothing.

## Alternatives rejected

- **`apply --yes` as the override:** bypassed by the panel and by every
  script. See decision 1.
- **Refusing in the `--detach` parent:** silent in the panel. See caller 1.
- **Asking `git fetch` for the remote's default branch:** needs a network;
  apply often runs offline.
- **Hard-coding `main`, as #2056 does:** right for the owner's repo, wrong
  for a user whose default is `master` or `trunk`. `origin/HEAD` first
  gives the same answer for `main` repos and the right one for the rest.
- **A NixOS activation check:** runs on every switch from any source,
  including `nixos-rebuild` by hand. That's Mode A territory, and it's the
  user's own business.
- **Three inline copies of the logic:** they would drift.

## Risks

- **The checkout and the reader are different users** on every installed
  machine that runs `autoUpdate` (root reading a user-owned repo), and
  `safe.directory` is what makes that work. It can't be simulated in a
  sandbox (one uid), so the plan tests it on p620 as root
  (`sudo nixarchy-branch-guard /etc/nixos`). A regression here would
  **refuse on every such machine**, which is loud rather than silent, but
  still a regression.
- **A user who works on branches on purpose** now needs the override. The
  message says how, in one line.
- **`origin/HEAD` is often unset** in clones made with `git init` + `remote
  add`. Then the default is `main`, and a `master` repo refuses until
  `git remote set-head origin -a` is run once. The refusal message should
  say that when it applies (default guessed, not read).
- **`autoUpdate` starts failing daily** on a machine left on a branch. That's
  intended, and the failure names the branch.

## Verification

| what | how | break it by |
|---|---|---|
| the rules | `checks.branch-guard`, a `runCommand` that builds throwaway repos: on main, on a feature branch, detached at `origin/main`, detached elsewhere, `origin/HEAD` → `master` and on master, no remote, not a repo, `#attr` suffix, override on a feature branch | deleting the detached-HEAD rule: the "detached at origin/main" case must go red |
| `omarchy-update` refuses | the same check runs the shipped script against a feature-branch repo, and the refusal text must appear before any `nh` | removing its guard call |
| `apply` and `autoUpdate` refuse | their generated scripts must call the guard before their first write/build line, read from a fixture's evaluated config | removing either call; the §1 break shows each assertion can fail |
| the panel shows it | `checks.session` if it can put the flake on a branch, otherwise a documented hole and a p620 step | — |
| a checkout owned by another user | on p620: `sudo nixarchy-branch-guard /etc/nixos` (root reading the user's repo, the `autoUpdate` case) answers without "dubious ownership", on main and on a branch | — |
