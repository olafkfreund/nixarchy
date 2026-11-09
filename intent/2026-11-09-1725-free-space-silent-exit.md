---
status: draft
issue: 1725
author: x
---

# Intent: a free-space install that stops after partitioning says why, and stops less

## Problem

`checks.free-space` failed on PR #1724 (run 42590009405, 2026-11-09). That PR
changes no installer code, and `main`'s next install check passed with the
same installer, so the failure is intermittent.

The guest kernel listed `vdb: vdb1 vdb2 vdb3 vdb4`, which means sgdisk created
nixarchy's two partitions. About four seconds later `nixarchy-install` exited 1.
The last line of `/var/log/nixarchy-install.log` is sgdisk's own "The operation
has completed successfully." No line says what failed.

`installer/install.sh` has a set of `|| return 1` exits that print nothing.
Between sgdisk and formatting, those are:

- `check_free_partitions` (`:1868-1881`): `readlink -f` and `lsblk -nro PKNAME`.
- `check_disks` (`:904-936`), which it calls: `readlink -f`, and four `lsblk`
  calls with stderr sent to `/dev/null`.
- The same two functions run again from `format_disk` (`:1884`, `:1965`).

One of these fired, and the log cannot say which. That is the same failure as
the bug itself, from the user's side: on a real machine, beside somebody's
Windows, the install stops with partitions already on the disk and gives no
reason. The refusal rule in `installer/AGENTS.md` is "refuse in sentences".

The likely cause, which is inferred and not reproduced:

- The settle loop (`:1837-1846`) stops waiting as soon as both
  `/dev/disk/by-partlabel/nixarchy-{esp,root}` links exist.
- The `partx -u` just before it (`:1830`) can make the kernel re-read the
  table, after which udev removes and re-creates those links.
- `readlink -f` succeeds on a link that is missing at that moment, because
  only its final component is absent.
- `lsblk` on the returned path then fails, and the function returns 1 in
  silence.

## Proposed outcome

- Every exit from the free-space path between partitioning and formatting
  prints one line naming the call that failed and its target. A failure like
  run 42590009405 would then say which one it was.
- If the race is real, the check waits it out. Either way, a free-space install
  does not fail on a partition that exists but whose link is briefly missing.
- A cheap check can fail for each of those two behaviours, in
  `tests/installer-disk-identity.nix`, the stubbed check that already sources
  these functions.

## Affected users and systems

- Anyone using `disk_mode=free`, which installs beside an existing OS. This is
  the riskiest mode, because the disk holds somebody else's data.
- Whole-disk installs reach `check_disks` from `format_disk` and would gain the
  same messages, and nothing else.
- CI: `install-check.yml`'s `install` job, which builds `free-space`. A flaky
  failure there also blocks unrelated pull requests, as it did #1724.

## Constraints

- No change to which disks are accepted. The identity checks (WWN, serial,
  size, model, by-path, and "the partitions belong to the selected disk") stay
  exactly as strict. A retry must never accept a partition on another disk.
- No new destructive step. `wipefs` still touches only the two partitions this
  run created, after they are proven ours.
- Messages follow the existing register: `nixarchy-install: …`, then what was
  and was not written. They must not claim "nothing was written", because the
  partitions exist by this point.
- Prove each check fails (CLAUDE.md §1). A break must be shown to land before
  a green result is read.
- Test locally first, by tier (§6): the cheap stubbed check, then
  `checks.free-space` and `checks.install` in a VM slot when no runner is busy.
  This applies before any push.

## Open questions

1. **Messages only, or the race fix too?** I propose both: messages alone leave
   the flake in CI. The race fix is the one that needs the spec to prove the
   cause, and if it cannot be proven, the spec says so and ships messages only.
   Do you agree?
2. Should the remaining silent `|| return 1` exits elsewhere in `install.sh` (for
   example `free_region`) be in scope, or only the post-partition path? I
   propose only the free-space path from `free_space_possible` through
   `format_disk`, to keep the diff reviewable.
