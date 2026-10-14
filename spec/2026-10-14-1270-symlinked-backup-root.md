---
status: draft
issue: 1270
intent: intent/2026-10-14-1270-symlinked-backup-root.md
---

# Spec: the home backup sees an allowlist directory that is a symlink

## Design

All changes are in `pkgs/omarchy/nix-bin/nixarchy-home-backup`, with cases in
`tests/home-backup-restore.nix`.

### 1. Walk through a symlinked entry (`allowlisted_files`, `:278`)

On the home side only (`$root == $home_root`), when `$root/$entry` is a
symlink to a directory, the walk starts at `"$root/$entry/"`. With the
trailing slash, `find -P` resolves the starting point and lists what is
under it. Paths still come out as `$root/$entry/<name>`, so the existing
`rel` prefix check (`$rel == "$entry/"*`) and the exclusion matching work
unchanged.

The restore side (`$root != $home_root`) keeps refusing a symlinked
component, as the intent requires.

### 2. Nothing else in the out-of-list check changes (`credential_hits`)

This check, from #1269, already builds its include roots with `realpath -m`,
which resolves a directory link. So for `.config/hypr -> ~/dotfiles/hypr`,
the root becomes `~/dotfiles/hypr`. That is the approved decision 2 as it
stands:

- plain files under the linked directory are not links, so they are not
  checked, and their real location is inside the root anyway;
- a file *inside* that directory which is itself a link to somewhere else is
  `-L` and goes through the existing review;
- the exclude roots go through `realpath -m` too, so an excluded file under
  a symlinked `.local/state/omarchy` stays excluded.

### 3. Show where a symlinked entry really points (`:500`)

The "What would be backed up" listing prints each include with
`includes | sed 's/^/    /'`. It becomes a short loop. An entry that is a
symlink gets its resolved target on the same line:

    .config/hypr/  ->  /home/u/dotfiles/hypr

This prints before the `gum confirm "Back this up?"` prompt.

**Why this line exists, and why it answers the intent's constraint.** The
intent says the fix must not let `~/.config/hypr -> ~/.aws` copy
credentials unasked. Decision 2 trusts a directory link's target wherever
it points, so the content scan is the only other line of defence, and it
misses an AWS file: it needs a quoted value, and
`aws_secret_access_key = …` is unquoted. Showing the target on every run
turns a silent trust into a visible one, answered by the prompt the user is
already given. That is weaker than a refusal. The alternatives below say
why a refusal was not chosen.

## Alternatives rejected

- **Trust a directory target only inside `$HOME` minus known credential
  directories** (`.ssh`, `.aws`, `.gnupg`, `.kube` …): a denylist that is
  incomplete by construction. It reads as protection and isn't.
- **Send every file under a linked directory to the credential review.**
  This contradicts approved decision 2, and it prompts on every run for the
  stow layout this issue exists for.
- **Name the entry as skipped instead of following it.** That is open
  question 1, decided the other way at approval.
- **`find -L` for the whole walk.** It follows every link at any depth,
  including file links, and would bypass the `-L` test in `credential_hits`.
  A file reached through `-L` is still a link on disk, so the check would
  still fire, but loops and very large trees become possible. The trailing
  slash follows exactly one link, the entry itself.

## Risks

- A user whose `.config/hypr` links to a directory holding secrets gets
  them backed up after one confirm. The resolved path is shown right above
  that confirm. That's accepted under decision 2, and the PR says so.
- **Nested directory links** inside an entry
  (`.config/hypr/conf.d -> elsewhere`) are still not descended into, by the
  same `find -P` rule. This is unchanged, out of scope, and named in the PR
  as the remaining case.
- The restore and the allowlist format are untouched. The backup gains
  files it used to miss, so the first run after the upgrade commits them.
  That is the fix.

## Verification

Three new backup cases in `home-backup-restore`. The first two are red on
today's code (§1):

| case | setup | expect | today |
|---|---|---|---|
| `backup-dir-link` | `.config/hypr -> $home/dotfiles/hypr` containing `hyprland.conf` | `.config/hypr/hyprland.conf` committed; no `outside the backup list`; log shows `.config/hypr` with `->` and the target | **red**: nothing under it committed |
| `backup-dir-link-inner` | the same, plus `dotfiles/hypr/secret.conf -> $home/.aws/credentials`; the stub declines `anyway` | the review names `secret.conf` and `outside the backup list`; nothing committed | **red**: no review line |
| `backup-dir-link-store` | `.config/hypr ->` a store directory | its files committed, no review line | red today too (nothing walked); stays green after |

Then the existing cases, the `grep-q-pipefail` and #847 `shell.json`
guards (both tripped on #1269, so the tests avoid `| grep -q` and never write
`shell.json`), `nix fmt -- --ci`, statix and deadnix.

The work is two files and two steps (test, then fix). Per the managed
policy, that is below the coder handoff threshold, so the session model
implements it.
