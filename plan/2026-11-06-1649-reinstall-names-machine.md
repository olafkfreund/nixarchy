---
status: draft
issue: 1649
spec: spec/2026-11-06-1649-reinstall-names-machine.md
coders:
  2: codex  # the launcher's either/neither logic and the one-commit repo derivation
  4: codex  # the missing-disk step: small, tricky, guarded shell
  6: codex  # stubbed checks across three files
  7: codex  # manual and release-note prose
reviewers:
  - codex  # read-only review of each commit; agy was dropped by the owner on 2026-11-06
---

# Plan: A reinstall image installs the machine it was built from

## Approved decisions

- `mkUserIso` passes `host` in `source`; the published image passes none and is unchanged.
- `installer/cd.nix`, when `source.host` is set, builds a bare git repository: one commit of `source.flake.outPath`, fixed identity and date, no history, no remote. The launcher names its store path.
- The launcher adds `--from file://<repo> --host <name>` only if `/proc/cmdline` named neither `nixarchy.from=` nor `nixarchy.host=`. Both named: those win. One named: nothing added, and `main()`'s existing "needs both" refusal fires.
- `cd.nix` exposes `system.build.installerLauncher`; `mkUserIso` returns the image with an `installerLauncher` attribute so a check goes through `mkUserIso`.
- `clone_repo` drops `origin` for `file:///nix/store/` URLs; the commit stays.
- A missing-disk step runs before `confirm_repo_disks` for any interactive `--from` install of an existing host. It acts only when the host has exactly one disk, it is absent here, `hosts/<name>/default.nix` holds it as a literal `device = "<path>";` with `mode = "whole";`, and no answers file is in use. It offers `disk_rows` (#1653, stacked; one PR), rewrites the path, `git add`s. Every other case keeps today's refusal.
- `nixarchy-reinstall-iso` drops `refuse_stock_image` and defaults to `$FLAKE#<this host>` (the bare per-host attribute every generated flake has). `NIXARCHY_REINSTALL_ATTR` still overrides.
- Manual and release notes; full install of a personal image stays a named hole.

## Steps

0. **Stack on #1653.** `git merge fix/1653-disk-list` once its step 1 is committed, so `disk_rows` exists. → `git log --oneline` shows it.

1. **`flake.nix:1702-1712` (`mkUserIso`).** `source = { inherit flake host; };` and return `sys.config.system.build.isoImage // { inherit (sys.config.system.build) installerLauncher; }` with `sys` bound in the `let`. → `nix eval` of `installerLauncher` through `lib.mkUserIso` on a fixture (step 6).
   Traps: `nix fmt` after the edit (hook reformats); §5 every commit changes every derivation, so compare drvPaths in one tree only.

2. **`installer/cd.nix:9-80, :327`.** `repo = lib.optionalString (source ? host) "${runCommand ...}"`: copy `source.flake.outPath` writable, `git init`, `add -A`, commit with `GIT_AUTHOR_*`/`GIT_COMMITTER_*` fixed to `nixarchy <nixarchy@localhost>` and date `@0`, then `git clone --bare` into `$out`. Launcher: set `named=1` on either `nixarchy.from=` or `nixarchy.host=`; after the loop, if `named` is unset and the image has a repo, append `--from file://$repo --host $host`. `system.build.installerLauncher = nixarchyInstallerLauncher;`. → step 6's check.
   Traps: `''${` escaping in the Nix string, and `\$` is literal (§5, #1504); a module argument can't have a `?` default, so use `source.host or null`; the published image's launcher must stay byte-identical in behaviour.

3. **`installer/install.sh` `clone_repo` (:1556).** After the clone: `case $from_repo in file:///nix/store/*) git -C "$work" remote remove origin ;; esac`. → step 6.

4. **`installer/install.sh`, new `replace_missing_disk()` beside `confirm_repo_disks` (:1623), called just before it (~:2964).** Return 0 unless `from_host_exists` and `answers_file` is empty. Read the disks as `confirm_repo_disks` does; act only on one disk that `[ -e ]` fails for. `grep -c` for `device = "<path>";` and `mode = "whole";` in `$hostdir/default.nix`, each exactly once; otherwise return 0 and let the existing refusal speak. Say the saved disk is missing, `disk_rows | gum choose` with `ask_device`'s flags, `sed` the literal path, `git -C "$work" add`. → step 6's disk cases.
   Traps: `set -e` doesn't reach inside `$(...)` (§5): `out=$(cmd) || return`; escape the path for `sed` (`/dev/disk/by-id/...` holds `/` and `:`); `checks.grep-q-pipefail`.

5. **`pkgs/omarchy/nix-bin/nixarchy-reinstall-iso:44, :333-346`.** Delete `refuse_stock_image` and its call; `REINSTALL_ATTR="${NIXARCHY_REINSTALL_ATTR:-$FLAKE#$(cat /proc/sys/kernel/hostname)}"` (the installer names `hosts/<name>` after the hostname). → `checks.reinstall-iso`.

6. **Checks.** New `tests/reinstall-image.nix` + `flake.nix` `checks.reinstall-image`: calls `lib.mkUserIso` on a fixture flake and host, reads `installerLauncher` and the repo it names, stubs `/proc/cmdline` and the final `exec`; cases from the spec (none named → pair; both → theirs; one → only that, and the extracted `main()` refuses; `clone_repo` sees the host and no `origin`; absent host takes the "adding it" branch; published launcher adds nothing; wrong host throws). `tests/installer-from-repo.nix`: disk cases (missing+one candidate rewritten and staged; present untouched; several disks, free mode, non-literal device, answers file all refuse with nothing written). `tests/reinstall-iso.nix:163`: drop the `^refuse_stock_image$` probe, assert the default attribute names the host. → the five §1 breaks from the spec, each red, output kept.
   Traps: §5 `git add`; `mkFlake.nix` needs a committed tree, so commit before building; `printf` not heredoc in Nix strings; prove each break landed.

7. **Docs.** `docs/manual/reinstall-image.md`: remove "Not available right now"; the one-commit `/etc/nixos` and `nixarchy config repo`; a different disk; the questions it asks (consent, network, password, recovery password, disks; no username). `tests/install-matrix.py` row and `tests/AGENTS.md` sentence for the full-install hole. Release notes and Discussions text. → `docs`, `release-notes`, `readme-counts` checks.

8. **Local proof (no repo edit), VM tier.** Build one image from a throwaway generated flake and boot it until the installer names the host. Result in the PR; a full install on it is stated as run or not run.

## Tests

`nix fmt -- --ci`, `statix`, `deadnix`, `grep-q-pipefail`, `reinstall-image`, `reinstall-iso`, `installer-from-repo`, `installer-disk-list`, `installer-ui`, `installer-wizard`, `iso-source`, every target `generated-checks.sh` prints. Not run locally: the `install` job, named in the PR.

## Rollback

Revert the merge commit (both issues). `refuse_stock_image` returns with it. An image already built carries its repo and launcher, which only matters to whoever boots it.
