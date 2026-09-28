---
status: approved
issue: 1037
spec: spec/2026-09-28-1037-apply-branch-guard.md
---

# Plan: rebuilding from the flake checkout refuses a branch nobody chose to deploy

## Approved decisions, carried from the spec

- **One helper, `nixarchy-branch-guard <flake>`** (`writeShellApplication`,
  with `git` and `coreutils`), used by all three callers.
- **The rules, offline, from local refs only:**
  - the default branch is `refs/remotes/origin/HEAD` if set, otherwise
    `main`;
  - "on it" means the current branch has that name, or HEAD is detached at
    exactly `refs/remotes/origin/<default>`, the same as nixos_config #2056;
  - no remote → proceed;
  - not a git work tree, or not a local directory (a `#attr` suffix is
    stripped first) → proceed;
  - `ALLOW_BRANCH_DEPLOY=1` → proceed;
  - otherwise exit 1, with a message naming the branch and short rev, how to
    switch back, and the override. When the default was guessed rather than
    read, it also says `git remote set-head origin -a`.
- **Every git call is read-only with `-c safe.directory=<dir>`**, because the
  checkout and the reader are different users: `autoUpdate` runs as root
  against the user-owned `/etc/nixos`.
- **The override is `ALLOW_BRANCH_DEPLOY=1`**, not `apply --yes`.
- **Callers:**
  - `nixarchy-apply` checks right after `flake=` (`modules/apps.nix:3398`),
    before any write or `git add`. It is **skipped in the `--detach`
    parent**, so the refusal fails the unit, which the panel shows. The
    detach block forwards `ALLOW_BRANCH_DEPLOY` with `--setenv`.
  - `omarchy-update` checks before `nh os switch --update`.
  - `autoUpdate` checks after the dirty-tree check and before
    `nix flake update nixpkgs`.

## Steps

**0. Before any local build:** `gh run list … | length` must print 0 (§6).
Repeated before steps 5, 6 and 7.

1. **`pkgs/branch-guard.nix`**, the helper, following the rules above. The
   refusal message follows the spec's text.
   → verify: `nix build` of it, then run it by hand against three scratch
   repos (main, a feature branch, detached at `origin/main`) and read the
   exit codes and the message.

2. **Expose it.** `flake.nix` `packages.nixarchy-branch-guard =
   callPackage ./pkgs/branch-guard.nix { }`, next to
   `nixarchy-sops-policy-add`. Callers take it by `callPackage` of the same
   file (the same derivation), as `pkgs/secret.nix` does with
   `sops-policy-add.nix`.

3. **The callers.**
   - `modules/apps.nix`: the guard in `nixarchy-apply`'s `runtimeInputs`;
     after `flake=`, `[ -n "$detach" ] || nixarchy-branch-guard "$flake"`;
     in the detach block,
     `--setenv=ALLOW_BRANCH_DEPLOY="''${ALLOW_BRANCH_DEPLOY:-}"`.
   - `pkgs/omarchy/nix-bin/omarchy-update`: `nixarchy-branch-guard "$flake"`
     right after the flake is resolved and validated (before its other
     checks, so a refusal is the first thing said). The helper goes into
     Omarchy's runtime list in `pkgs/omarchy/default.nix`, in the explicit
     list whose note says "a missing entry should be a readable diff".
   - `modules/auto-update.nix`: the guard in the unit's `path`, called after
     the dirty-tree block and before `nix flake update nixpkgs`.
   Then `nix fmt` and read `git diff --stat` (the nixpkgs-fmt hook, §5).
   → verify: `statix`, `deadnix`, and `nix eval` of the vm configuration's
   toplevel `drvPath` (evaluation only).

4. **`tests/branch-guard.nix` → `checks.branch-guard`**, a `runCommand`
   modelled on `tests/apply-staging.nix`. It takes the real scripts from
   `nixosConfigurations.vm` without building the system, and uses `printf`,
   not heredocs, inside the Nix string (§5).
   - **The helper**, against throwaway repos with a local bare "origin":
     on main → 0; on a feature branch → 1 with the branch named; detached at
     `origin/main` → 0; detached elsewhere → 1; `origin/HEAD` → `master`
     and on master → 0, and on main there → 1; no remote → 0; not a repo →
     0; `<dir>#host` → the same answer as `<dir>`; feature branch with
     `ALLOW_BRANCH_DEPLOY=1` → 0; `origin/HEAD` unset on a `master` repo →
     1, and the message mentions `set-head`.
   - **`nixarchy-apply`**, taken from `vm`'s `systemPackages`, against a
     feature-branch repo (`NIXARCHY_FLAKE=<repo>`): exits non-zero, prints
     the refusal, and **the repo is byte-for-byte untouched** (`git status
     --porcelain` empty, and no `nixarchy/` written). With `--detach`, the
     parent does not refuse. That is asserted from the script, because
     `systemd-run` can't run in a sandbox: the call is guarded by
     `[ -n "$detach" ] ||`, and the detach block forwards
     `ALLOW_BRANCH_DEPLOY`. This is the one part checked by reading text
     rather than running.
   - **`omarchy-update`**, from the built Omarchy package: the same repo,
     the refusal printed, and no `nh` reached. It is proven by the message
     alone, since `nh` isn't on the sandbox PATH and would fail differently.
   - **`autoUpdate`**: `vm` extended with `autoUpdate.enable = true`. Its
     `script` is written to a file and run with the guard and git on PATH.
     It must refuse, and the repo's `flake.lock` must be unchanged.
   → verify: `nix build .#checks.x86_64-linux.branch-guard` green.

5. **Red (§1), one break per part.** Commit a baseline first. Each break is
   proven with `git diff`, then built, then restored with
   `git checkout HEAD -- <file>`:
   - the helper's detached-HEAD rule deleted → "detached at origin/main"
     goes red;
   - the helper's `safe.directory` removed → **not visible in the sandbox**
     (one uid). Recorded as such, not claimed; step 7 covers it;
   - apply's guard call removed → the apply part goes red;
   - omarchy-update's call removed → its part goes red;
   - autoUpdate's call removed → its part goes red;
   - the `--setenv` forward removed → the detach assertion goes red.
   Every red output is captured for the PR.

6. **Session / panel.** Check whether `checks.session` can put
   `/etc/nixos` (its flake) on a branch cheaply. If it can: panel rebuild
   → failed unit whose journal shows the refusal. If not: a sentence in
   `tests/AGENTS.md` naming the hole, and step 7 covers it by hand.

7. **p620, by hand, read-only** (nothing is rebuilt):
   `sudo nixarchy-branch-guard /etc/nixos` from the branch's build result,
   run as root against the user-owned checkout. It must answer on main with
   no "dubious ownership". Checked on a feature branch only in a scratch
   worktree, never by switching `/etc/nixos`'s branch.

8. **Docs.** `tests/AGENTS.md`: the check, and what it can't see
   (ownership, the live panel). `docs/manual`: one paragraph where rebuilding
   is described (grep first), naming `ALLOW_BRANCH_DEPLOY`. If a manual
   page is added, it must be in all three lists (`docs/AGENTS.md`).

9. **PR.** Squash the implementation into one commit with a full-sentence
   subject, keeping the artifact commits. Put every red in the template, and
   link all three artifacts. `Closes #1037`. Before opening: `read_new`;
   post only if a trap qualifies.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.branch-guard` | green |
| the same with each step-5 break | red at that part |
| `nix fmt -- --ci`, statix, deadnix | exit 0 |
| `sudo nixarchy-branch-guard /etc/nixos` on p620 (main) | exit 0, no ownership error |

## Rollback

Revert the commit. The three callers return to building whatever is checked
out, and the helper and check go. No state on any machine changes. Anyone
who set `ALLOW_BRANCH_DEPLOY` is unaffected either way.
