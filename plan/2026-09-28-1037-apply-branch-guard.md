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

## Deviations found while implementing

- **`apply`'s check sits just before the detach block (`:3487`), not right
  after `flake=` (`:3398`).** Between the two, `apply` handles its read-only
  modes: `--status`, `--json` and the journal follow. They read and exit.
  With the check at `flake=`, a checkout on a branch would have refused a
  status query. Just before the detach block is still before any write (the
  first is the `git add` near `:3663`), and the `[ -n "$detach" ] ||`
  condition is unchanged. The panel itself polls `nixarchy-rebuild-state`,
  so it was never affected.
- **`omarchy-update`'s check sits after the "no flake directory" test and
  before the #356 writability prompt**, so a refused branch is the first
  thing said, and the script never offers to `chown` a checkout it is about
  to refuse.
- **Step 1 confirmed `-c safe.directory` is honoured:** git 2.55's
  `git-config(1)` puts the command scope in protected configuration.

- **The spec overstated why `-c safe.directory` is needed.** It said that
  without it the guard "would error on exactly the machines it exists for",
  with `autoUpdate` as root reading the user-owned `/etc/nixos`. But
  `modules/nixos.nix:967` already sets `safe.directory = [ cfg.flake ]`
  system-wide on every nixarchy machine (plus the resolved path, `:1128`),
  so root's git trusts the managed flake. Measured on p620: root's plain
  `git` reads `/etc/nixos` with `SUDO_UID` removed, because
  `/etc/gitconfig` carries the entry. The `-c` is kept, and only matters when
  `NIXARCHY_FLAKE` points somewhere the system config doesn't name.
  `installer/cd.nix:850` confirms `-c` reaches only the command it is passed
  to, which is exactly how the helper uses it. Step 7 still runs, but
  "no dubious ownership" there is already guaranteed by the module; it proves
  the helper answers as root, not that `-c` was needed.
- **A suspected second bug was measured and ruled out.** It looked as though
  `autoUpdate`'s existing dirty-tree `git -C` (as root) would fail on
  installed machines before reaching the guard. It doesn't, for the same
  reason (`nixos.nix:967`). Nothing to file.

- **`autoUpdate` calls the helper by store path, as the spec says; the plan
  had put it in the unit's `path`.** `tests/options.nix` already runs the
  generated script under a `PATH` of its own (`PATH="$PWD/au-stubs:$PATH"`),
  with no helper on it. A bare name would have failed there with "command not
  found", the `|| { note; exit 1; }` would have fired, and existing
  `checks.options` cases ("auto-update refused the installer's staged flake")
  would have gone red on a change that looks unrelated to them. Found by
  reading `tests/AGENTS.md` ("run a unit's script, do not grep it") before
  building. None of the existing harnesses that run `apply` or `autoUpdate`
  have a remote, so the helper lets all of them through.
- **The check's `printf | grep -q` pipes are here-strings.** Under the
  `pipefail` every `runCommand` has, `grep -q` exiting at its first match can
  SIGPIPE the writer and read as a miss (`tests/AGENTS.md`).

- **Step 6 took the `checks.session` branch.** Its existing detach block
  already runs `apply --detach --yes` against real systemd. Two cases were
  added next to it, against a git repo with an origin on a feature branch:
  - without the override: the parent starts the unit rather than refusing,
    and the unit ends `exit-code` with the refusal in its journal;
  - with `ALLOW_BRANCH_DEPLOY=1`: the refusal is absent from that run's
    journal.
  Each run's journal is scoped with `--invocation`, as `apply`'s own log
  mode does, and it must not be empty, so a filter that matches nothing
  can't pass the override case by default. So the detach parent's skip and
  the `--setenv` forward are now proven by running, not only by reading the
  script in `checks.branch-guard`.

- **The "helper ships" assertion checks the system `PATH`, not Omarchy's
  closure.** The first version asserted the helper was in the Omarchy
  package's runtime closure, and failed. That was correct of it, because
  `runtimeDeps` is `passthru`. The package's `bin/` is an unwrapped symlink
  farm (`bin/omarchy` reads each script's header to list its commands), and
  the commands reach a machine through the module's `systemPackages`
  (`modules/nixos.nix:1189`). The property `omarchy-update` depends on is
  "the helper is on the machine's `PATH`", so the check reads
  `vm.config.environment.systemPackages`, passed in as a yes/no value rather
  than a store path.
- **The four output captures are `&& rc=0 || rc=$?`**, not `; rc=$?`. The
  builder runs with `errexit`, so the first expected refusal (exit 1) ended
  the check at the assignment with no message, right after "on main -> 0".
  That's the trap `tests/AGENTS.md` records.

- **Step 7, measured on p620, and it covered more than planned.** As root
  with `SUDO_UID`/`SUDO_USER`/`SUDO_GID` removed (as under systemd), the
  helper answers exit 0 on `/etc/nixos`, which is on main. Since
  `/etc/nixos` is system-trusted, that alone can't show the helper's `-c`
  doing anything, so the same was run on a `git clone --shared` in scratch
  space, owned by the user and **not** system-trusted:
  - plain root `git` refuses it (`detected dubious ownership`);
  - the helper refuses its feature branch with the right message and passes
    its main.
  So the `-c safe.directory` path the sandbox can't reach is proven on a
  real root/user split. The clone was removed; `/etc/nixos`'s branch was
  never changed.
- **The `autoUpdate` case gained a lock-moving `nix` stub** (the one
  `tests/options.nix` uses). The first round of red runs showed "leaves
  flake.lock untouched" staying green with the guard removed, because
  without `nix` in the sandbox the update failed before touching the lock.
  With the stub, that break turns it red ("moved the lock on a refused
  branch").

- **`checks.apply-detach-interface` was retargeted: it read the unit's
  command through a fixed window.** CI's `omarchy` job went red on #1046 with
  "`--expect-sha256` is accepted but not forwarded by the systemd-run call".
  The forward was intact. The check ran `grep -A6` from the `systemd-run`
  line, and the new `--setenv=ALLOW_BRANCH_DEPLOY` line pushed the forward to
  the seventh line. It encoded the arrangement (within six lines) rather than
  the property (the command forwards it), so it now reads the whole
  continued command with `awk`. Proven against the shipped script: the new
  extraction finds the forward in the 8-line command; the old `grep -A6`
  misses it, reproducing the CI failure; and with the forward removed, the
  new extraction goes red. **Missed locally because only `branch-guard` and
  `session` were run.** Every `apply-*` check drives the same script, so all
  of them are run before the next push.

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
