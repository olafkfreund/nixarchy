---
status: approved
issue: 1268
spec: spec/2026-10-14-1268-review-findings.md
---

# Plan: fix the findings from the 2026-10-14 cross-model code review

## Approved decisions, carried over

- **Two PRs.** PR A, on `fix/1268-review-findings` (worktree
  `/mnt/data/vmtest/nixarchy-1268`), carries items 1, 2, 3, 4, 6 and 7. PR B
  carries item 5 and is opened **after PR A merges**, on a new branch from
  the updated `main`, so the artifacts are already there to link and the PR
  is not stacked (§8).
- **Order** (the owner's choice: data loss and secrets first): steps 1–2
  (items 1, 2), step 3 (item 4), step 4 (item 3), steps 5–6 (items 6, 7),
  step 7 (finish PR A), step 8 (PR B).
- **Item 1:** the marker `$REPO/.git/nixarchy-home-backup`. An unmarked
  `.git` at the default path is adopted. A missing or empty `$REPO` is
  created and marked. Anything else is refused before any write, with the
  adopt command. `git clone` on restore marks too. The guard before `rm -rf`
  tests the marker.
- **Item 2:** an `awk` pass. A file without a top-level `sops:` block, or
  with any non-empty scalar outside it not starting with `ENC[`, is
  plaintext. Name the key, never the value. The warning and
  `gum confirm --default=false` flow stay.
- **Item 3:** never a refusal. A home-side symlink whose `realpath` is
  outside `/nix/store/` and outside every include root becomes a
  `credential_hits` line, and the existing default-no prompt decides.
- **Item 4:** `|| exit 2` with an `::error::` on the closure pipeline.
- **Item 5:** one anchored pattern,
  `^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$`, applied to **both** `latest`
  and `current` in the step that produces them. No `env:` migration.
- **Item 6:** separator `\037` in `rebuild_state` and both readers.
- **Item 7:** `git rm .tar.gz`.

## Rules for every step

- **§1, prove each check fails on today's code.** Commit the new test cases
  first (test-only commit), build the check, capture the red output to
  `/mnt/data/vmtest/1268-red-<step>.log`, then make the fix and watch it go
  green. Before calling a green run "not blind", `git diff` to prove the
  break landed (§1). Restore with `git checkout HEAD -- <path>`, never
  `git checkout -- <path>` (§5).
- **§5:** a flake only sees tracked files, so `git add` before every build.
  Cheap checks only, one at a time:
  `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.<name> --print-build-logs`
  (§6 tier 1). Do not pipe a build whose status you need (§1).
- **§5:** in a `.nix` test, never add a new heredoc. Use `printf '%s\n'`.
  Inside a Nix `''` string, write `''${` for a shell `${`. After any `.nix`
  edit, run `nix fmt` and read `git diff --stat` (a hook may reformat with
  nixpkgs-fmt).
- Commit subjects are full sentences, with no conventional-commit prefix
  (§8).
- Cite the step number in each commit body.

## Steps

### Step 1 — item 1: the backup empties only a repository it owns

`pkgs/omarchy/nix-bin/nixarchy-home-backup` is plain bash (no Nix
interpolation).

**1a. Test first**, in `tests/home-backup-restore.nix`:

- Add a stub `gum` on `PATH` (not `pkgs.gum`), like
  `tests/config-repo-ownership.nix:19` does:
  `confirm` succeeds unless the arguments contain `anyway` (the
  credential prompt), and `choose` prints `Nowhere for now`. Write it with
  `printf '%s\n'`. The shebang is `${pkgs.bash}/bin/bash`.
- Add a `backup()` helper beside `restore()` (`:24`):
  `HOME=$home NIXARCHY_HOME_BACKUP_REPO=$repo NIXARCHY_FLAKE=$flake bash ${script} backup > "$log" 2>&1`.
  Set `git config --global user.name/user.email` under that `HOME` so the
  identity prompt is skipped. Check whether `setup()` (`:16`) can be reused.
  It pre-creates `$repo/.git`, so the new cases need their own setup.
- Every backup case creates `$home/.config/omarchy/shell.json` (the first
  shipped allowlist entry, in `shipped_list`) so there is something to
  back up.
- Case `backup-foreign-dir`: `$repo` holds `keep.txt` and no `.git`. Expect
  the run to fail, `keep.txt` to be byte-identical, `$repo/.git` to be
  absent, and the log to name `nixarchy-home-backup` (the adopt command).
  **Red today:** `keep.txt` is deleted.
- Case `backup-foreign-git`: `$repo` is a `git init`ed repo with a commit and
  an uncommitted `wip.txt`. Expect refusal, with `wip.txt` intact. **Red
  today.**
- Case `backup-default-upgrade`: unset `NIXARCHY_HOME_BACKUP_REPO`, so the
  default `$home/.local/share/nixarchy/home-backup` is used. Pre-create it
  as an unmarked repo with one commit. Expect success, the marker to exist,
  and `shell.json` committed. Green today and must stay green (upgrade
  path).
- Case `backup-fresh`: `$repo` does not exist. Expect success and the
  marker.

Build `home-backup-restore`, then capture the red output.

**1b. Fix:**

- `:33`: introduce `DEFAULT_REPO=$HOME/.local/share/nixarchy/home-backup`
  and `REPO=${NIXARCHY_HOME_BACKUP_REPO:-$DEFAULT_REPO}`, plus
  `MARKER=$REPO/.git/nixarchy-home-backup`. Compare `${REPO%/}` with
  `$DEFAULT_REPO` when adopting.
- Replace the repository block (`:499-504`) with the four-row table from
  the design:
  - marked: proceed.
  - `.git`, unmarked, default path: `: > "$MARKER"`.
  - `$REPO` exists and is not a directory, **or** `find "$REPO" -mindepth 1 -maxdepth 1 -print -quit`
    prints anything: `fail`, then `say` the adopt command
    `touch "$REPO/.git/nixarchy-home-backup"` (only meaningful when `.git`
    exists; otherwise say to choose an empty or new directory). `exit 1`.
  - otherwise: the existing `mkdir -p` + `git init`, then `: > "$MARKER"`.
- `:554` guard: `[[ -e $MARKER ]] || { fail "$REPO was not created by this backup; refusing to empty it."; exit 1; }`.
- Restore, `:365-369`: after a successful `git clone`, `: > "$REPO/.git/nixarchy-home-backup"`.
- Keep the existing `:550-553` comment and add one line: the guard tests
  ownership, not `.git`, because the script creates `.git` itself.

Green: `home-backup-restore` passes, all old restore cases included.

**Commits:** the test commit (red), then the fix commit.

### Step 2 — item 2: every secrets value encrypted

`pkgs/omarchy/nix-bin/nixarchy-config-repo` is plain bash. `gawk` is
already in the runtime list (`pkgs/omarchy/default.nix:20,200`).

**2a. Test first**, in `tests/config-repo-ownership.nix`:

- Add `pkgs.gawk`, `pkgs.age` and `pkgs.sops` to `nativeBuildInputs`.
- Change the gum stub (`:19-20`) so `confirm` fails when its arguments
  contain `Commit anyway`. Existing cases have no secrets file and never see
  that prompt, so they are unaffected. Prove it by keeping them green.
- Generate a real sops file the way `tests/secret-enroll.nix:41-61` does
  (`age-keygen`, a `.sops.yaml` with one creation rule, then
  `sops -e -i hosts/alpha/secrets.yaml` from a plaintext
  `hypr-rdp-password: s3cret-value`), so the fixture is sops' actual output
  rather than a guess at it.
- Case `secrets-encrypted`: that file in the flake. Expect success, a
  commit made, and no `NOT encrypted` in the output.
- Case `secrets-mixed`: the same encrypted file plus an appended line
  `extra-token: plain-value-123`. Expect `NOT encrypted` with
  `extra-token` in the output, no commit in the flake
  (`git -C "$NIXARCHY_FLAKE" rev-parse HEAD` fails), and `plain-value-123`
  **absent** from the output. **Red today:** the file passes and is
  committed.
- Case `secrets-plain`: plaintext only, with no `sops:` block. Expect
  refusal. This is green today, and the case keeps it from regressing.

**2b. Fix** (`:398-409`): replace the per-file `grep -q` with:

```bash
first_plain() { # prints the first unencrypted key, or a reason; nothing when the file is sops-clean
  awk '
    /^sops:/ { meta = 1; exit }
    /^[[:space:]]*(#|$)/ { next }
    {
      line = $0; sub(/^[[:space:]]*(- )*/, "", line); key = ""
      if (match(line, /^[^:]+:([[:space:]]|$)/)) { key = substr(line, 1, RLENGTH); line = substr(line, RLENGTH + 1) }
      sub(/^[[:space:]]+/, "", line)
      if (line != "" && line !~ /^ENC\[/) { sub(/:[[:space:]]*$/, "", key); print (key != "" ? key : "a list item"); found = 1; exit }
    }
    END { if (!found && !meta) print "no sops metadata" }' "$1"
}
```

Then, per file: `why=$(first_plain "$f")` and
`[[ -n $why ]] && plain+="    ${f#"$FLAKE"/}  ($why)"$'\n'`. This also drops
the stray `''${` Nix escape on today's `:406`. The file is plain bash, where
`''` is an empty string that worked by accident.

- Update the `:400-404` comment to say each value is checked, not the file.
- The `say` line "none of these has one" becomes "each has a value sops did
  not encrypt".
- Add a `# shortcut:` line: line-oriented over sops' own single-line
  `ENC[...]` output; a hand-written block scalar is flagged, not parsed.
  Upgrade to `yq` only if a valid sops file is ever flagged.

Green: `config-repo-ownership` passes, all old cases included.

### Step 3 — item 4: `cache-budget.sh` fails when it cannot measure

**3a. Test first**, in `tests/cache-budget.nix`:

- Add `".#flaky": { "/nix/store/hhh-flaky": $((7 * MiB)) }` to
  `store.json` (inside the existing heredoc, `:48-55`; no new heredoc).
- In the stub's `"path-info -r")` branch (`:70`), first line:
  `[ "\$4" = .#flaky ] && exit 1`. `build --no-link` still succeeds for
  it.
- Case (g), after (b): `bash $budget .#small .#flaky` must exit non-zero
  and print `.#flaky`. **Red today:** it passes at 10 MiB.

**3b. Fix**, `.github/scripts/cache-budget.sh:45-47`: append to the
pipeline
`|| { echo "::error::could not read the closure of $e, so its cost cannot be measured" >&2; exit 2; }`.

Green: `cache-budget` passes (a)–(g).

### Step 4 — item 3: out-of-list symlinks reach the credential review

**4a. Test first**, in `tests/home-backup-restore.nix`, with the step 1
harness:

- Case `backup-link-out`: `$home/.aws/credentials` holds `secret`.
  `$home/.config/hypr/hyprland.conf` is a symlink to it (`.config/hypr/` is
  a directory entry on the shipped list). Expect the log to name `hyprland.conf` and
  `outside the backup list`. With the stub answering no to `anyway`, expect
  no commit and no `credentials` content anywhere under `$repo`. **Red
  today:** it is copied and committed.
- Case `backup-link-store`: a symlink on the list pointing at a store file
  (`${pkgs.bash}/bin/bash` is in the sandbox). Expect no `outside the
  backup list`, and the file copied. Green today and must stay green.

**4b. Fix**, `credential_hits` (`:313`):

- At the top of the function, build the include roots without a process
  substitution (§4, `mapfile < <(cmd)` hides failure):
  `local inc; inc=$(includes) || return 1`. Then for each non-empty line:
  `roots+=("$(realpath -m -- "$home_root/${line%/}")")`. Use `realpath -m`
  on the roots too, so a `$HOME` that is itself a symlink (`/home` →
  `/mnt/…`) does not make every link look external.
- First thing inside the per-file loop:

  ```bash
  if [[ -L $HOME/$rel ]]; then
    target=$(realpath -- "$HOME/$rel") || target=unresolvable
    inside=false
    [[ $target == /nix/store/* ]] && inside=true
    for r in "${roots[@]}"; do [[ $target == "$r" || $target == "$r"/* ]] && inside=true; done
    [[ $inside == true ]] || { echo "$rel  (a link to $target, outside the backup list)"; continue; }
  fi
  ```

- Check the caller (`:520-545`) treats a non-zero `credential_hits` as a
  failure, not as "no hits". If it does `hits=$(credential_hits)` without
  checking, add `|| { fail …; exit 1; }`.

Green: `home-backup-restore` passes, including step 1's cases.

### Step 5 — item 6: `rebuild_state` keeps empty fields

`modules/apps.nix` holds the script inside a Nix `''` string.

**5a. Test first**, in `tests/apply-detach-interface.nix`. That file's
comment (`:47-58`) says `--status` cannot be reached because `systemctl` is
in `runtimeInputs`, so go through the function itself:

- `fn=$(sed -n '/^ *rebuild_state() {$/,/^ *}$/p' "$apply")`. Then assert it
  is non-empty and ends in `}`, so a sed that matched nothing cannot pass
  (§1).
- `reader=$(grep -m1 'read -r st res code inv' "$apply")`, asserted
  non-empty. This is the script's real reader line, so the test exercises
  both halves.
- In a subshell: define
  `systemctl() { printf '%s\n' SubState=failed Result= ExecMainStatus=42 InvocationID=abc; }`
  (a shell function beats `PATH`), `eval "$fn"`, `eval "$reader"`, and then
  assert `code=42` and `inv=abc`.
- Update the `:47-58` comment and `tests/AGENTS.md`'s matching sentence:
  the field split is now covered, and the `none`/`succeeded` mapping is
  still unverified.
- **Red today:** `code=abc`, `inv` is empty.

**5b. Fix** (`modules/apps.nix`):

- First, `grep -n 'rebuild_state' modules/apps.nix pkgs -r` to confirm the
  only consumers are `:3484` and `:3512`. If there's another, stop and
  update the plan (§4, widening a format).
- `:3446-3480`: every `printf '…\t%s\t%s\t%s\n'` becomes
  `printf '…\037%s\037%s\037%s\n'`, and `printf 'none\t\t\t\n'` becomes
  `printf 'none\037\037\037\n'`.
- `:3484` and `:3512`: `IFS=$'\t'` becomes `IFS=$'\037'`.
- One comment line above `rebuild_state`: a non-whitespace separator,
  because `read` collapses empty tab fields (AGENTS.md §13).
- Out of scope, but name it in the PR: the other `IFS=$'\t' read` at
  `:1703`, `:2867`, `:3044` and `:3069` were not audited.

Green: `apply-detach-interface` passes.

### Step 6 — item 7

`git rm .tar.gz`. No check.

### Step 7 — finish PR A

- `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`,
  `nix run nixpkgs#deadnix -- --fail .`.
- Rebuild the four checks once more on the final tree, one at a time.
- Check that `git merge-base origin/main HEAD` equals the current
  `origin/main` after a fetch, and that `git show --stat` lists only
  intended files (§5). Rebase if `main` moved (§9).
- Post to the agent bus only if something non-obvious was learned (§9).
- Open PR A using the template. Link all three artifacts. Paste each step's
  red log. Say which steps the `coder` agent did. Use `Refs #1268`, **not**
  `Closes`, because PR B is still outstanding (§8). Give the body no skip-CI
  marker (§8). Before reporting it as merging, check
  `gh pr view --json mergeable` (§8).

### Step 8 — PR B: item 5 (after PR A merges)

- New branch `fix/1268-omarchy-tag` from the updated `main`, in a new
  worktree.
- `.github/workflows/omarchy.yml:55`: replace the `^v[0-9]` test with
  `[[ "$latest" =~ ^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$ ]]`. After `current`
  is computed (`:56`), add the same test for `current`, each with the
  existing `::error::` shape.
- Proof, since no PR run reaches this workflow (§3: name the hole): a
  `#!/usr/bin/env bash` script under `/mnt/data/vmtest/` (bash, not zsh,
  §1) that runs the old and the new conditionals over `v4.0.0-beta3`,
  `v4.0.2`, `v5$(id)`, `v5;x` and an empty string. Paste both outputs: old
  accepts the injection tags, new refuses them, and both accept the real
  tags. Also confirm `git ls-remote --tags` shows every existing upstream tag
  passing the new pattern.
- `actionlint` on the file, if it is not in a run of CI (§6 tier 1).
- PR body: `closes #1268`, and state that it's a CI-gate change for a human
  to merge (§11).

## Tests

| check | expected after the plan |
|---|---|
| `home-backup-restore` | green, with 6 new backup cases; red on today's code for foreign-dir, foreign-git, link-out |
| `config-repo-ownership` | green, with 3 new cases; red today for secrets-mixed |
| `cache-budget` | green (a)–(g); red today for (g) |
| `apply-detach-interface` | green; red today for the empty-`Result` split |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

Every step is its own test commit and fix commit. Revert the fix commit to
undo a step; the test commit then goes red, which is how it should be.
Revert PR A's merge commit to undo all of it. Existing backups are not
migrated, only marked, so a rollback leaves a stray empty marker file
inside `.git` and nothing else.

## Handoff

The plan has more than three file-editing steps, so per the managed policy,
steps 1–6 go to one `coder` agent (step 1 first, then each later step by
`SendMessage`). A fresh `opus` reviewer, given this plan and `git diff`,
reviews afterwards. Steps 7 and 8 stay with the session model.
