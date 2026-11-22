---
status: approved
issue: 1907
intent: intent/2026-11-22-1907-first-install-cleanup.md
---

# Spec: quattro's first-install launcher cleanup keeps what the user owns

## Design

`pkgs/omarchy/quattro-user-files.sh` (edge-only, sourced from installPhase) replaces
the loop body `rm -f ~/.local/share/applications/"${launcher##*/}"` with a guarded
delete: remove only a regular file that is not a symlink and whose content equals
the shipped launcher. The substitution runs only where the pin's script contains
that line, so main's tag and older edge pins build unchanged, and `--replace-fail`
breaks the build if upstream rewords the line while keeping it.

Content is compared with bash (`$(<a) == $(<b)`), not `cmp`: `diffutils` is not in
the package's runtime list, and a vendored script must not depend on the caller's
PATH for it.

`checks.first-install-launchers` (`tests/first-install-launchers.nix`, cheap
`runCommand`) cuts the cleanup block out of the built script and runs it against a
home holding a pristine copy, an edited copy, a symlink to a byte-identical copy
and a symlink to an edited copy. Only the pristine copy may go. On a pin without
the cleanup it reports skipped, and fails if the loop is present but not cut out.

## Alternatives rejected

- A check that only nothing reaches `--first-install`: a user can type it, so the
  delete would still take their links.
- Dropping the cleanup: a stale seeded launcher from another region would then
  survive a first install, which is what upstream added it to stop.
- `cmp -s`: a new runtime dependency for one comparison.

## Risks

A pristine launcher the user deliberately kept is still removed on a first
install, as upstream intends. The bash comparison ignores trailing newlines, so a
copy differing only in those counts as pristine.

## Verification

Break: drop the patch; the check fails naming the identical Home Manager link and
the edited copy. Restore; it passes. Run under the carry pin, main's tag and the
efcf615 fallback pin.
