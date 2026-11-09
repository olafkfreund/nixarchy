---
status: draft
issue: 1725
intent: intent/2026-11-09-1725-free-space-silent-exit.md
---

# Spec: a free-space install waits out udev's second re-read, and every exit names its call

## Evidence: the race is real

The intent left the race fix conditional on proof. A throwaway VM probe
(`/mnt/data/vmtest/probe-1725/flake.nix`, not committed) gives that proof. It
builds the `free-space` fixture's disk (`tests/free-space.nix:356-394`), then
runs `installer/install.sh:1817-1846` verbatim, three times. It logs guest
uptime at each step beside `udevadm monitor --udev -s block`, which stamps
events with the same clock.

| run | settle loop | udev events on the new partitions after `sgdisk` returns |
|---|---|---|
| 0 | 1 wait, passed at 20.78 | add, remove, add; all finished by 20.27 |
| 1 | **0 waits, passed at 31.22** | remove 31.154, add 31.215, **remove vdb3 31.230, add vdb3 31.262** |
| 2 | 0 waits, passed at 42.28 | remove 42.208, add 42.257 |

Two facts, both measured:

1. **Every run re-reads the partition table twice.** sgdisk's own `BLKRRPART`
   is the first. udev's inotify watch on the whole disk is the second: when
   sgdisk closes `/dev/vdb` after writing, udevd synthesises a change, which
   for a whole disk re-reads the table. Every partition is then removed and
   added again, and its `by-partlabel` link with it.
2. **The loop can pass before the second re-read lands.** `until [ -b … ]`
   tests before it settles. In runs 1 and 2 the links from the first re-read
   were already present, so `udevadm settle` never ran. In run 1, vdb3, which
   holds `nixarchy-esp`, was removed 8 ms after the loop passed.

On an idle host, `check_free_partitions` usually finishes inside those 8 ms,
or after the re-add. On a loaded CI runner it can land in the gap. The link is
then missing while `/dev/disk/by-partlabel` still exists, so `readlink -f`
prints the path unchanged and exits 0, which I measured. `lsblk -nro PKNAME`
on that path fails, and `check_free_partitions` returns 1 with no message.

That matches run 42590009405. The log shows no wipefs error, which rules out
`wipefs` at `:1863` and points at the silent exits before it. wipefs does not
remove links: the probe polled both links for 8 s after it and saw none
missing.

## Design

### 1. The settle loop waits for udev's own re-read (`installer/install.sh:1836-1846`)

```bash
  # udev re-reads the table a second time once sgdisk closes the disk (its
  # inotify watch), removing and re-adding every partition. Settle before
  # looking, and look again after a pause, so the links read are the stable ones.
  waited=0
  until udevadm settle && [ -b "$esp_dev" ] && [ -b "$root_dev" ] &&
    sleep 1 && udevadm settle && [ -b "$esp_dev" ] && [ -b "$root_dev" ]; do
    waited=$((waited + 1))
    if [ "$waited" -gt 30 ]; then
      …unchanged message…
    fi
    sleep 0.5
  done
```

- **Settle first.** The links are tested only after udev's queue is empty.
  That is the defect the probe shows.
- **A second settle after one second.** The watch-triggered re-read arrived
  0.4 to 0.6 s after sgdisk in every probe run. udevd may not have queued it
  when the first settle returns, so the pause covers that gap. The second
  `[ -b ]` then proves the links survived the re-read.
- The bound stays at 30 rounds and its message is unchanged. A round now
  costs at least 1.5 s rather than 0.5 s, so the worst case grows from about
  15 s to about 45 s, on a path that fails in either case.

### 2. `check_free_partitions` refuses a link that does not resolve to a partition (`:1868-1881`)

After `real=$(readlink -f "$part")`, test `[ -b "$real" ]`. A missing link
resolves to its own path and then fails, with a message saying so, instead of
reaching `lsblk`. The parent test (`:1875-1879`) is unchanged and still fails
closed.

This is not a retry. The function is called after step 1's wait (`:1848`)
and after the disko build (`:1965`), each time against the current links.
Wiping still requires that both links resolve to block devices on the
selected disk. The guard in front of `wipefs` stays exactly as it is
(intent constraint): a parent-disk check, not proof of creation.

### 3. Every silent exit names its call

Messages follow the house register. What each says must be true at every
call site (intent constraint).

| site | call | message (stderr) |
|---|---|---|
| `check_disks` `:912` | `readlink -f "$path"` | `nixarchy-install: could not resolve $path. Nothing further was formatted; start again.` |
| `check_disks` `:918-921` | the four `lsblk` reads | one guard for the four: `nixarchy-install: lsblk could not read the WWN, serial, size or model of $real. Nothing further was formatted; start again.` |
| `check_free_partitions` `:1871` | `readlink -f "$device"` | `nixarchy-install: could not resolve $device.` plus the existing second line |
| `check_free_partitions` `:1873` | `readlink -f "$part"` | `nixarchy-install: could not resolve $part.` plus the existing second line |
| new, step 2 | `[ -b "$real" ]` | `nixarchy-install: $part does not resolve to a partition ($real).` plus the existing second line |
| `check_free_partitions` `:1874` | `lsblk -nro PKNAME` | `nixarchy-install: lsblk could not read the parent disk of $real.` plus the existing second line |
| `partition_free_space` `:1863` | `wipefs -a` | `nixarchy-install: wipefs could not clear $esp_dev and $root_dev (exit N).` and `  The partitions exist; nothing was formatted. Inspect before retrying.` |
| `format_disk` `:1969-1972` | LUKS key write | `nixarchy-install: could not write the LUKS key file. Nothing was formatted.` |

- "The existing second line" is `:1877`'s `Partition entries may exist and
  signatures may have been cleared. Inspect before retrying.` It is true at
  both call sites (`:1848`, `:1965`).
- `check_disks` keeps "Nothing further was formatted", which is true before
  sgdisk (`:1816`, `:1884`) and after it (`:1963`, `:1870`). That is agy's
  intent finding.
- The key write runs after `check_free_partitions` at `:1965` and before disko.
  "Nothing was formatted" is therefore true in both modes, and in free mode
  the partitions' existence is already reported by the earlier lines.
- The four `lsblk` reads share one guard, `a=$(…) && b=$(…) && … || { …; }`. They
  read the same device, and the message names all four fields.

### 4. A check that can fail: `tests/installer-disk-identity.nix`

This is the existing stubbed `runCommand`, which already sources these
functions from `installer/install.sh`. It runs in seconds. Additions:

- **The re-read model.** A `udevadm` stub models udev's queue with two
  pending re-reads:
  - `udevadm settle` processes the first and arms the second, as the watch
    does.
  - The second becomes due only after a `sleep`. A `sleep` stub marks time
    passing and does not actually sleep.
  - The next settle processes it.

  A stubbed `check_free_partitions`, on the `partition_free_space` path only,
  fails if any re-read is still pending when it runs. The real function keeps
  its own cases.
  - Today's loop never settles with links present, so it reaches the check
    with both re-reads pending: **red**.
  - A loop that settles first but only once leaves the second pending: red.
  - Step 1's loop: green.
- **Every message.** One case per row of step 3's table. The call is made to
  fail, and the test asserts exit 1 and a `grep -F` for the call and its
  target. The `[ -b "$real" ]` case resolves a link to a missing file.
- Existing fixtures need two adjustments:
  - The `sed` that maps `[ -b` to `[ -e` for `partition_free_space`
    (`:231`) also covers `check_free_partitions`, now that it tests `-b`.
  - `/dev/esp` and `/dev/root` map to fixture files.
  - `udevadm` and `sleep` are stubbed. agy noted that today's fixture passes
    only because the loop never calls `udevadm`.

### 5. `installer/AGENTS.md`

Add one bullet under "Things that are true and easy to get wrong": udev
re-reads a partition table a second time after a partitioner closes the disk,
so links seen straight after sgdisk can vanish. Settle before looking, and
again after a pause. It cites this spec's table. The lesson is specific to
the installer, so it goes in that directory's register, not CLAUDE.md.

## Alternatives rejected

- **`flock` the disk around sgdisk** (systemd's block-device locking, which
  makes udevd hold off). udevd processes the device again when the lock is
  released, so the second re-read still follows, only later. It also adds a
  dependency on how udevd handles locks, for no smaller window.
- **Retrying inside `check_free_partitions` on a missing link.** It puts a
  wait inside a guard whose job is to fail closed, and still leaves `wipefs`
  and disko addressing links that may be mid-re-read. One stable wait before
  any of them is simpler, and step 2 makes a missed case loud rather than
  silent.
- **Dropping the `partx -u`.** The probe shows partx is not the second
  re-read: the inotify watch is. partx is the documented fallback for a disk
  with a mounted partition (`:1828-1829`), which a real dual-boot machine may
  have.
- **`udevadm trigger --settle` on the disk.** A userspace-triggered change
  does not wait for the inotify synthesis, which is the event at issue.
- **A separate message per `lsblk` field.** Four near-identical guards for one
  device read, where one message naming all four fields says which call
  family failed.

## Risks

- **The one-second pause is measured, not guaranteed.** On a host far slower
  than any probe run, udevd could queue its re-read after the second settle.
  The loop would then pass and the re-read land later, which is today's race
  with a far smaller window. Step 2 turns that case into a named refusal
  rather than a silent exit 1. If it is ever seen, the message says so.
- **A slower install by about 1.5 s** in free-space mode. Whole-disk mode does
  not run this loop.
- **Message text tested by `grep`.** `checks.installer-refusal` and
  `installer-ui` match other installer messages. Before changing a line, the
  plan greps `tests/` for each existing message it touches.
- **Real hardware:** NVMe partition names (`p1`) do not matter here: every
  path goes through `by-partlabel` and `readlink -f`, as today.

## Verification

1. **`checks.installer-disk-identity` passes.** §1 breaks, each shown failing,
   with `git diff` proving the break landed:
   1. restore today's loop → the re-read case fails ("re-read pending");
   2. settle first but drop the pause and second settle → it fails again;
   3. drop the `[ -b "$real" ]` test → the missing-link case fails (the
      message is absent);
   4. revert any one message → that row's case fails.
2. **The probe, re-run against step 1's loop**, three times, as one run, not
   a loop until something happens. Expect no `remove` of vdb3 or vdb4 after
   the loop's pass time in any run. The output goes in the PR, with today's
   loop's run 1 as the before.
3. **VM tier locally, before pushing**, by §6's gate (no busy self-hosted
   runner, no p620 build): `checks.free-space` and `checks.install`. Whole
   disk does not run the loop but does reach `check_disks`'s new messages.
   `installer-refusal` too, since it reads installer stderr.
4. **Cheap tier:** `nix fmt -- --ci`, statix, deadnix, `grep-q-pipefail`,
   `test-registration`, `installer-ui`, and every target
   `.github/scripts/generated-checks.sh` prints that this change reaches.
5. **Not run locally:** `install-encrypted` and `install-iso-net`, which are
   nightly-only. The PR says so. The LUKS key-write message is covered by the
   stubbed check.
6. **After merge:** the next `install-check` runs on `main` and the nightly.
   One green run proves little about an intermittent race, which is why the
   probe in step 2 is the evidence.
