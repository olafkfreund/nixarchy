---
status: draft
issue: 1268
intent: intent/2026-10-14-1268-review-findings.md
---

# Spec: fix the findings from the 2026-10-14 cross-model code review

Two pull requests, per the intent's recorded decisions: **PR A** carries items
1–4, 6 and 7; **PR B** carries item 5 (a CI-gate change, merged by a human).
Item numbers follow the intent.

## Design

### 1. The backup empties only a repository it created (`nixarchy-home-backup`)

An ownership marker, `$REPO/.git/nixarchy-home-backup`, is written whenever
the script creates the repository. It lives inside `.git`, so it is never
committed, pushed or restored.

The repository step (today `:499-504`) becomes:

| state of `$REPO` | action |
|---|---|
| `.git` and marker | proceed |
| `.git`, no marker, `$REPO` is the default path | adopt: write the marker, proceed |
| missing, or an empty directory | `git init`, write the marker |
| anything else | refuse before touching anything, and name the one command that adopts it (`touch "$REPO/.git/nixarchy-home-backup"`) |

Only the script ever creates the default path
(`$HOME/.local/share/nixarchy/home-backup`), so adopting it unmarked is what
lets every existing backup keep working after the upgrade (intent constraint).
The restore path's `git clone` (`:365`) also writes the marker after a
successful clone. `git clone` already refuses a non-empty target.

The guard before the `rm -rf` (`:554`) tests for the marker instead of `.git`.
That guard is the one that failed: the script had just created the `.git` it
was checking for.

### 2. Every value in `secrets.yaml` must be encrypted (`nixarchy-config-repo`)

The one-line `grep -q 'ENC\[AES256_GCM'` (`:406`) is replaced with an `awk`
pass over each `secrets.y{a,}ml`. The file counts as plaintext when either:

- it has no top-level `sops:` block. sops writes that block into every file
  it encrypts, and without it the file cannot be decrypted anyway. Or
- any scalar value outside the `sops:` block (`key: value` or `- value`, after
  stripping comments) is non-empty and does not start with `ENC[`.

sops writes every encrypted value as a single-line `ENC[...]` scalar, so a
block scalar (`key: |`) written by hand is flagged as well, which is the
conservative answer. A key using sops' `_unencrypted` suffix is also flagged.
That costs one extra confirm prompt for a rare setup, and never a silent
push. The warning text and the `gum confirm --default=false` flow stay as
they are. The output also names the first plaintext key, but never prints its
value.

`awk` is not in coreutils. The plan has to
check that `gawk` reaches the script's runtime PATH (§7, `runtimeInputs`).

### 3. Symlinks out of the allowlist go through the credential review (`nixarchy-home-backup`)

They are not refused outright: a user who manages `~/.config` with GNU stow
has every file as a symlink into `~/dotfiles`. Refusing would make the
backup fail for them on every run, which breaks the intent's constraint the
same way refusing store links would.

`credential_hits` gains one rule. For each selected file that is a symlink on
the home side, resolve it with `realpath`. If the target is under neither
`/nix/store/` nor `$HOME/<entry>` for any allowlist include entry, report it
as a hit: `<rel>  (a link to <target>, outside the backup list)`. The
existing prompt, `gum confirm --default=false "Back it up anyway?"`, then
decides. Its default is no, so an unattended run copies nothing it was not
asked to.

### 4. `cache-budget.sh` fails when it cannot measure

The `nix path-info -r --json "$e" | jq …` pipeline (`:45`) gets
`|| { echo "::error::could not read the closure of $e" >&2; exit 2; }`.
`pipefail` is already set, so a failed `nix` fails the pipeline. Exit 2
matches the existing "does not build" error a few lines above.

### 5. The upstream tag is validated at its source (`omarchy.yml`) — PR B

The tag is interpolated into shell at more than fifteen places (`:67`, `:80`,
`:125`, `:137-139`, `:175`, `:205-206`, `:243-244`, `:562`, `:576`, and the
`with:` block at `:459-463`). `current` comes from our own `flake.nix` and
reaches the same places. Both are validated once, in the step that produces
them (`:55`), against a full anchored pattern that admits upstream's real
tags, `v4.0.0-beta3` included:

    ^v[0-9]+(\.[0-9]+)*(-[A-Za-z0-9.]+)?$

Neither value can reach `$GITHUB_OUTPUT` without matching. That leaves no
metacharacter for any later interpolation to carry.

### 6. `rebuild_state` keeps empty fields (`modules/apps.nix`)

`rebuild_state` (`:3446`) emits its four fields with the ASCII unit separator
`\037` instead of a tab. Both readers (`:3484`, `:3512`) use `IFS=$'\037'`.
Unlike tab, a non-whitespace `IFS` character delimits empty fields one by
one, so `failed<US><US>42<US>id` reads as four fields. The function is
private to the script, so no other consumer changes format. The plan greps
for that before changing it (§4, "widening a format").

### 7. `git rm .tar.gz`

## Alternatives rejected

- **Item 1, deleting only the paths the previous commit recorded.** It would
  also protect a user-supplied dotfiles repository. But it turns "emptied
  first" into a diff with its own failure modes (renames, a first run with
  no previous commit), and the intent's decision chose the marker.
- **Item 2, `sops filestatus`.** It reports only whether sops metadata
  exists, which is the same single-signal mistake as today's grep. It also
  makes `sops` a runtime dependency of `config-repo`.
- **Item 2, parsing with `yq`.** Correct, but it adds a dependency for
  something a line-oriented check over sops' own output format can answer.
- **Item 3, refusing every out-of-tree symlink.** It breaks stow users on
  every run (see Design).
- **Item 5, moving every interpolation to `env:`.** This is the textbook
  fix, but it means editing fifteen-plus sites in a workflow nobody can run
  from a PR. Anchoring the source closes the same hole with a three-line
  diff. Moving values to `env:` remains a fine follow-up.
- **Item 6, `mapfile`/`read -a` on the tab output.** These split with the
  same whitespace rule as `read`, so they don't fix it.

## Risks

- **Item 1:** anyone who already pointed `NIXARCHY_HOME_BACKUP_REPO` at a
  non-default repository *that the script created* is refused once after the
  upgrade, with the one-line command that adopts it. That's the price of
  refusing unknown directories, and the message makes it a ten-second fix.
- **Item 2:** a valid sops file in a layout the awk does not expect would
  be flagged when it shouldn't be. The cost is a confirm prompt, never a
  leak. The check covers both the real sops output from `secret-enroll`'s
  fixture shape and the hand-written cases.
- **Item 3:** stow users get one extra prompt on each backup run. The
  answer to that prompt is not remembered.
- **Item 5:** a future upstream tag outside the pattern (say `v5.0.0+build`)
  stops the bump job, loudly, with the existing `::error::` line. That is
  the right failure: a human reads it.
- **Item 6:** none beyond the format change. The two readers are the only
  consumers.

No host config, option or Mode A state changes.

## Verification

Each logic change extends a check that already drives the real script, and
each is proven red on today's code first (§1, failing output in the PR):

| item | check | red case on today's code |
|---|---|---|
| 1 | `home-backup-restore` gains backup-mode cases | a non-empty unmarked `$REPO` survives a backup run byte-for-byte. Today its files are deleted |
| 1 | same | the default path, unmarked with a prior commit, still backs up (upgrade path) |
| 2 | `config-repo-ownership` gains secret cases | a `secrets.yaml` with one `ENC[...]` value and one plaintext value is refused. Today it is committed |
| 2 | same | a sops-shaped, fully encrypted file passes |
| 3 | `home-backup-restore` | a `~/.config/hypr` link to a file outside the list is named in the review and, with `confirm` stubbed to "no", not copied |
| 3 | same | a link into a store-like path outside `$HOME` is copied without a prompt (the stub root stands in for `/nix/store`, or the case uses a real store path from the build) |
| 4 | `cache-budget` gains case (g) | an entry whose stub `path-info` exits 1 makes the budget exit 2. Today it passes |
| 6 | `apply-detach-interface` | the extracted `rebuild_state` with a stubbed `systemctl` returning an empty `Result` reads `code=42`. Today `code` holds the invocation id |
| 5 | none in CI; a local bash run of the step's guard against `v4.0.0-beta3`, `v4.0.2`, `v5$(id)`, `v5;x` | the injection tags are accepted today |

Item 5 has no check that runs on a PR: the workflow fires on schedule and
dispatch. PR B shows the guard's local before/after output instead and says
so plainly (§3: name the hole).

Then `nix fmt -- --ci`, `statix`, `deadnix`. The four touched checks are
cheap `runCommand`s, run one at a time under the build lock (§6 tiers).
