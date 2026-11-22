---
status: approved
issue: 1907
author: x
---

# Intent: quattro's first-install launcher cleanup must not delete what the user owns

## Problem

Quattro's `omarchy-provision-user --first-install` deletes every shipped launcher
name from `~/.local/share/applications`, so the region's list can seed them again.
Upstream assumes `/etc/skel` put them there. On nixarchy that file can instead be a
Home Manager link or a launcher the user edited, and the loop deletes it all the
same, with no ownership test (CLAUDE.md §1, #1304).

Nothing nixarchy ships passes `--first-install`: upstream's callers are its ISO's
target chroot and `omarchy-provision-owner`, and nixarchy runs neither. A user can
still type `omarchy finalize user --first-install`.

## Proposed outcome

On edge, the cleanup removes only a launcher identical to the shipped file, and
never a symlink. A check proves it with a link to byte-identical content.

## Affected users and systems

Edge users (quattro pins that ship the cleanup). main's v4.5.0 tag has no cleanup.

## Constraints

Must hold under main's tag and older edge pins: patch only where the loop exists.
No new runtime dependency (`diffutils` is not in the package's runtime list).

## Open questions

None.
