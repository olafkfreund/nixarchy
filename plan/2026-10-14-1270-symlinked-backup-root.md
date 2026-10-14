---
status: approved
issue: 1270
spec: spec/2026-10-14-1270-symlinked-backup-root.md
---

# Plan: the home backup sees an allowlist directory that is a symlink

## Approved decisions, carried over

- Follow a symlinked allowlist directory, **home side only**. Restore keeps
  refusing a symlinked component.
- Follow exactly one link, the entry itself, by giving `find -P` the
  starting point with a trailing slash. No `find -L`.
- The directory's resolved target is an include root. `credential_hits`
  already does this through `realpath -m` on its roots (#1269), so it is
  **not edited**.
- The "What would be backed up" listing shows `entry  ->  target` for a
  symlinked include. This is the visible half of decision 2's accepted risk:
  `~/.config/hypr -> ~/.aws` backs up after one confirm.
- Out of scope, and named in the PR: directory links nested inside an
  entry.
- Two files: `pkgs/omarchy/nix-bin/nixarchy-home-backup` (plain bash, no Nix
  interpolation) and `tests/home-backup-restore.nix`. The session model
  implements, since this is below the coder handoff threshold.

## Rules

- §1: commit the test first, build it red, and keep the log at
  `/mnt/data/vmtest/1270-red.log`. Then fix and build green.
- §5: `git add` before every build. Build under
  `flock /mnt/data/vmtest/codex-build.lock`, one at a time. Don't pipe a
  build whose status you need. Use `nix fmt` and `git diff --stat` after
  every `.nix` edit. No new heredoc in the `.nix` test (`printf '%s\n'`).
- Guards that tripped #1269: no `… | grep -q` in the test
  (`checks.grep-q-pipefail`); never write `omarchy/shell.json`
  (the build.yml #847 step). Run `checks.grep-q-pipefail` locally too.

## Steps

### Step 1 — test first (`tests/home-backup-restore.nix`)

Insert before `case_name=backup-link-store` (`:247`). Reuse `bsetup` and
`backup`; the gum stub declines only `anyway`.

- `backup-dir-link`: `mkdir -p "$home/dotfiles/hypr" "$home/.config"`,
  `printf 'bind\n' > "$home/dotfiles/hypr/hyprland.conf"`,
  `ln -s "$home/dotfiles/hypr" "$home/.config/hypr"`. Run `backup`; it must
  succeed. Assert:
  `HOME=$home git -C "$repo" ls-files --error-unmatch .config/hypr/hyprland.conf`
  (no pipe); `outside the backup list` not in `$log`; `$log` has a line
  with `.config/hypr` and `->`, matched with `grep -q '\.config/hypr.*->'`
  on the file (not a pipe). **Red today:** the file is not committed.
- `backup-dir-link-inner`: the same layout, plus
  `printf 'aws-key-xyz\n' > "$home/.aws/credentials"` and
  `ln -s "$home/.aws/credentials" "$home/dotfiles/hypr/secret.conf"`. Run
  `backup`; it must exit 0, because declining is a clean stop. Assert: no
  commit (`git rev-parse HEAD` fails), `aws-key-xyz` nowhere under `$repo`
  outside `.git`, and `$log` matches `secret.conf.*outside the backup list`.
  **Red today:** no review line.
- `backup-dir-link-store`: `ln -s ${pkgs.hello}/bin "$home/.config/hypr"`
  (one small store file). Run `backup`; it must succeed. Assert
  `.config/hypr/hello` is committed and there is no
  `outside the backup list`.

`git add`, `nix fmt`, build `home-backup-restore` into
`/mnt/data/vmtest/1270-red.log`. It must fail on `backup-dir-link` for the
committed-file reason, not a harness error. Commit the test alone, with the
red line in the body.

### Step 2 — the fix (`nixarchy-home-backup`)

- **Walk, `:278`.** Before the `find`, set the start point:

  ```bash
  start=$root/$entry
  # A symlinked entry is walked through (#1270): the trailing slash makes
  # find -P resolve the starting point, and only that one link.
  [[ $root == "$home_root" && -L $start && -d $start ]] && start=$start/
  ```

  Then `find -P "$start" …`. Add `start` to the function's `local` list.
  Check that the paths printed for `start=…/hypr/` are `…/hypr/<name>` with
  no doubled slash, because `rel=${path#"$root/"}` and the
  `$rel == "$entry/"*` check depend on it. GNU find prints them that way.
  The case asserting `.config/hypr/hyprland.conf` proves it.
- **Listing, `:500`.** Replace `includes | sed 's/^/    /'` with:

  ```bash
  while IFS= read -r e; do
    [[ -n $e ]] || continue
    if [[ -L $HOME/${e%/} ]]; then
      printf '    %s  ->  %s\n' "$e" "$(realpath -m -- "$HOME/${e%/}")"
    else
      printf '    %s\n' "$e"
    fi
  done <<< "$(includes)"
  ```

  This is the one place `includes` feeds a process without a status check
  today too. Keep it as a here-string from `$(includes)`, not
  `< <(includes)`, so a failure isn't hidden further. The list was already
  read successfully a few lines above via `allowlisted_files`.
  `printf`, not `say`: `say` is `echo -e`, which would interpret a
  backslash in a path.
- Build `home-backup-restore` green into `/mnt/data/vmtest/1270-green.log`.
  Then build `grep-q-pipefail`, then run `nix fmt -- --ci`, statix and
  deadnix.

### Step 3 — PR

- Fetch, then confirm `git merge-base origin/main HEAD` is `origin/main`.
  `git show --stat` lists only the two files plus the artifacts.
- Push, then open the PR with the template filled: `closes #1270`; link all
  three artifacts; the red line; state decision 2's accepted risk and the
  nested-link limit; give the body no skip-CI marker (§8).
- Wait for every check to pass, then confirm the PR's head is ours and
  `gh pr view --json mergeable` reports it mergeable. Merge only on the
  owner's word.

## Tests

| check | expected |
|---|---|
| `home-backup-restore` | red at step 1 (`backup-dir-link`), green at step 2, all earlier cases green |
| `grep-q-pipefail` | green |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

Revert the fix commit. The test commit then goes red, which is how it
should be. Nothing is migrated: a backup taken with the fix only holds
extra files.
