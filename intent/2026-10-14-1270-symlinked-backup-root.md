---
status: approved
issue: 1270
author: olafkfreund
---

# Intent: the home backup sees an allowlist directory that is a symlink

## Problem

`nixarchy home backup` backs up nothing from an allowlist directory that is
itself a symlink, and it doesn't say so.

That is the normal layout for anyone who manages dotfiles with GNU stow
(`~/.config/hypr -> ~/dotfiles/hypr`), and for a home-manager
`mkOutOfStoreSymlink` of a whole directory. `allowlisted_files` strips the
trailing slash from each entry (`nixarchy-home-backup`, `entry=${entry%/}`)
and walks it with `find -P`. `-P` does not follow a symlink given as the
starting point, so the walk yields the link itself, which matches neither
`-type f` nor `-xtype f`, and nothing under it. Reproduced with plain `find`
on 2026-10-14 (#1270).

It stays invisible because the "Nothing on the allowlist exists" warning
fires only when *every* entry is empty. With `shell.json` present the backup
succeeds and reports a file count. For `.config/hypr/`, the keybindings and
monitors that are half the reason the command exists, it reports success
while backing up none of them.

## Proposed outcome

A backup run either copies the files under a symlinked allowlist directory,
or names that directory as skipped, with the reason. Either way it never
reports success while silently backing up nothing from an entry that exists.

## Affected users and systems

- Users of `nixarchy home backup` whose `.config/hypr/`,
  `.config/omarchy/themes/` or `.local/state/omarchy/` is a symlink, or who
  added such a directory to `backup.list`.
- Not restore: the restore side already refuses a symlinked path component
  on purpose (repository-side links are hostile input), and that stays.

## Constraints

- **The out-of-list check from #1269 must keep working.** Walking through a
  directory symlink yields plain files whose *parent* is the link. That
  check only looks at a file that is itself a link (`[[ -L $HOME/$rel ]]`),
  so a naive fix that just follows the directory would let
  `~/.config/hypr -> ~/.aws` copy credentials with no prompt. The fix has to
  judge where a file really lives, not just whether it is a link.
- The store exemption stays: a directory linked into `/nix/store` is how
  home-manager delivers config, and it must not prompt.
- A check that is red on today's code (AGENTS.md §1): a backup case with a
  symlinked `.config/hypr` whose files are missing from the commit today.
- No change to restore, to the allowlist format, or to Mode A.

## Open questions

1. Follow or name? Following backs up what the user expects and matches
   stow's intent. Naming as skipped is smaller and never reads a file from
   outside `$HOME`'s own tree. My recommendation is to follow: the
   out-of-list check already decides what may be copied, so following is
   safe as long as that check sees the real location.
2. When the directory's target is in the user's own dotfiles repo
   (`~/dotfiles/hypr`), should its files count as inside the list, the way
   a store target does, or go to the "Back it up anyway?" prompt? The prompt
   is safe, but it would ask on every run for exactly the setup this issue
   is about. Recommendation: treat the directory's own resolved target as an
   include root, so its files pass, while a link *inside* it that leads
   elsewhere still prompts.

## Decisions at approval

Approved by the owner on 2026-10-14 with the recommendations:

1. Follow a symlinked allowlist directory.
2. Its resolved target counts as an include root, so its files pass; a link
   *inside* it that leads elsewhere still goes to the credential review.
