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
After sgdisk and before disko formats, those are:

- `check_free_partitions` (`:1868-1881`): `readlink -f` and `lsblk -nro PKNAME`.
- `check_disks` (`:904-936`), which it calls: `readlink -f`, and four `lsblk`
  calls with stderr sent to `/dev/null`.
- `wipefs -a` (`:1863`). wipefs prints its own error, but the installer adds
  no line of its own.
- `format_disk` runs `check_disks` and `check_free_partitions` again after the
  disko build (`:1963-1965`), and writing the LUKS key file (`:1968-1972`) can
  return 1 with no message.

The settle loop's timeout (`:1840-1844`) already explains itself. `partx`
(`:1830`) ends in `|| true`, so it cannot exit. Which of the others fired is
not known: the log cannot say, and this intent does not claim it was an
identity call (Codex review). That is the same failure as
the bug itself, from the user's side: on a real machine, beside somebody's
Windows, the install stops with partitions already on the disk and gives no
reason. The refusal rule in `installer/AGENTS.md` is "refuse in sentences".

The likely cause, which is inferred and not reproduced:

- The settle loop (`:1837-1846`) stops waiting as soon as both
  `/dev/disk/by-partlabel/nixarchy-{esp,root}` links exist.
- The `partx -u` just before it (`:1830`) can make the kernel re-read the
  table, after which udev removes and re-creates those links.
- If a link is missing when `check_free_partitions` reads it, while
  `/dev/disk/by-partlabel` still exists, `readlink -f` succeeds and prints the
  path unchanged. GNU readlink accepts a missing final component when the
  parent directory exists, which I measured here. `lsblk` on that path then
  fails, and the function returns 1 in silence.
- If the whole directory is gone, `readlink -f` itself fails, again silently.
  A link that has already resolved to a device node is not affected by the
  link's later removal. Nothing in the log shows that `partx` caused the
  timing.
- The settle loop tests the links *before* it settles, so if they already
  exist, `udevadm settle` never runs while `partx`'s events are still queued.
- `wipefs -a` opens both partitions read-write. On close, udev processes them
  again, while the disko build runs. That points at the second check
  (`:1963-1965`) as much as the first (`:1848`). This is inferred (agy review).

## Proposed outcome

- Every exit from the free-space path between partitioning and formatting
  prints one line naming the call that failed and its target. A failure like
  run 42590009405 would then say which one it was.
- If the spec can show the race, a free-space install no longer fails on a
  partition that exists but whose link is briefly missing. That covers every
  user of those links: the identity checks, `wipefs` and disko's run. If it
  cannot show it, the spec says so and the change ships the messages alone.
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
- No new destructive step, and no weaker guard in front of `wipefs`.
  Today's guard is narrower than "proven ours". `check_free_partitions` proves
  that each global `by-partlabel` link resolves to a partition whose parent
  is the selected disk. It does not prove the entry is one this run created
  (Codex review). Any wait or retry must re-check the *current* link targets,
  fail closed, and run immediately before `wipefs`. Whether to strengthen the
  guard (by partition number or PARTUUID from sgdisk) is a question for the
  spec, not a requirement here.
- Messages follow the existing register: `nixarchy-install: …`, then what was
  and was not written. What each message says has to be true at every call
  site. `check_disks` also runs before sgdisk (`:1816`, `:1884`), so its
  messages keep the neutral "Nothing further was formatted"
  (`:915`, `:923`, `:931`). Only the post-sgdisk sites (`check_free_partitions`,
  `wipefs`) may say that partitions exist (agy review).
- `free_region` and `free_space_possible` print nothing, by design. They are
  read-only probes behind the wizard screen and report through `$free_why`
  (agy review).
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
2. Should the remaining silent `|| return 1` exits elsewhere in `install.sh`
   (for example `free_region`, which runs before sgdisk) be in scope? I
   propose only `partition_free_space`, `check_free_partitions`, `check_disks`
   and `format_disk`, from sgdisk to disko's run, to keep the diff reviewable.
   Codex and agy both agree.
