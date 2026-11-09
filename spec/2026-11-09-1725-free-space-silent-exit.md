---
status: approved
issue: 1725
intent: intent/2026-11-09-1725-free-space-silent-exit.md
---

# Spec: a free-space install settles after partitioning, and every exit names its call

## Evidence: the race is real

The intent left the race fix conditional on proof. A throwaway VM probe
(`/mnt/data/vmtest/probe-1725/`, not committed; its flake and logs go in the
PR) gives it. The probe:

- builds the `free-space` fixture's disk (`tests/free-space.nix:356-394`);
- runs `installer/install.sh:1817-1846` verbatim: sgdisk, then `partx`, then
  the settle loop;
- straight after the loop, makes 400 rounds of the two calls
  `check_free_partitions` makes on each link: `readlink -f`, then
  `lsblk -nro PKNAME`.

Each run is three iterations. Guest uptime is logged at each step beside
`udevadm monitor --udev -s block`, which stamps events with the same clock.

| loop | iteration | loop passed | udev events on the new partitions | failed rounds of 400 |
|---|---|---|---|---|
| today's (`run4.log`) | 0 | 0 waits, 20.10 | all done by 20.083 | 0 |
| | 1 | 0 waits, 36.93 | remove 36.962, add 37.016, **remove 37.027, add 37.071** | **3**: `readlink` root 36.99, `readlink` esp 37.02, `lsblk PKNAME` root 37.06 |
| | 2 | 0 waits, 53.92 | remove 53.951, add 53.994, **remove 54.004, add 54.044** | **3**: same three calls |
| design 1 (`run5-new.log`) | 0 | 23.17 | all done by 22.132 | 0 |
| | 1 | 41.24 | all done by 40.227 | 0 |
| | 2 | 59.22 | all done by 58.198 | 0 |

What this measures:

1. **The new partitions are removed and re-added more than once after
   sgdisk, and the last cycle can land after today's loop has passed.** The
   loop tests `[ -b ]` before it settles. In four of the six iterations on
   today's loop it passed with no settle at all, on links from an earlier
   cycle.
2. **Both of `check_free_partitions`' silent calls then fail.**
   - `readlink -f` on a link whose target node has gone fails.
   - On a link that has gone while `/dev/disk/by-partlabel` remains,
     `readlink -f` returns the path unchanged with exit 0. `lsblk` then fails
     on that path.

   Either is a silent `return 1` (`:1873`, `:1874`).
3. **Design 1's loop passes only after the last cycle.** Every event in the
   three iterations landed at most 0.21 s after sgdisk returned, against the
   loop's 1 s pause plus two settles. No round failed.

What it does not show:

- **Which of run 42590009405's exits fired.** This is the most likely
  mechanism, not a proof of that run.
- **What produces each re-read.** sgdisk's own re-read, `partx`, and udev's
  watch on a disk closed after writing all run back to back. The probe has no
  run without `partx`, and the fix does not depend on which one it is.
- **That `wipefs` never removes a link.** The background poll was too coarse
  to catch a 30 ms gap (agy). What does show it is `udevadm monitor`: it
  recorded no partition `remove` after the last re-read cycle, across the
  `wipefs` and the 8 s after it.

## Design

### 1. Settle after partitioning, until the links survive a second settle (`installer/install.sh:1836-1846`)

```bash
  # The new partitions are removed and re-added more than once after sgdisk
  # (spec/2026-11-09-1725-…). Settle before looking, and again after a pause,
  # so the links checked below are the last ones.
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

- The chain is an `until` condition, so errexit does not apply. The loop exits
  only when all seven commands succeed in one pass. Codex and agy agree.
- **Bound.** The limit is 30 failed rounds, not a wall-clock limit. A round
  that fails at the first `[ -b ]` costs one settle plus 0.5 s. One that
  fails after the pause costs two settles plus 1.5 s. `udevadm settle`'s own
  default timeout (120 s) bounds each settle. A failing settle is
  indistinguishable from an absent link, and both end in the existing
  "never appeared" message. That message is true either way, because the
  links were not seen stable.
- **The pause:** measured events end at most 0.21 s after sgdisk, so 1 s is
  about five times the largest observed gap.

### 2. `check_free_partitions` refuses what is not a partition, and hands back what it checked (`:1868-1881`)

- After `real=$(readlink -f "$part")`, test `[ -b "$real" ]` and refuse with a
  message.
- The function records the two resolved device nodes in globals,
  `free_esp_real` and `free_root_real`, after their parent check passes. The
  parent check (`:1875-1879`) is unchanged and still fails closed.

### 3. `wipefs` clears the device nodes that were checked, not the global links (`:1863`)

`wipefs -a "$free_esp_real" "$free_root_real"`.

Today `wipefs` re-reads the global `by-partlabel` links after
`check_free_partitions` has checked them. In the gap between the two, a link
could vanish or, in principle, be retargeted (Codex). A kernel device name
such as `/dev/vdb3` cannot move to another disk, so clearing the checked node
narrows that gap to the node itself. If the node itself has gone, `wipefs`
fails and step 5's message reports it.

This strengthens the guard before `wipefs`, as the intent requires, and
weakens nothing. The guard is still a parent-disk check, not proof of
creation.

### 4. A settle before the post-build check (`format_disk`, `:1963`)

`udevadm settle` before `check_disks` at `:1963`. That covers the change
events `wipefs`'s close produces, and anything else queued during the build,
so the check and disko's run read settled links (Codex). disko addresses the
links itself; this spec does not change disko.

### 5. Every silent exit names its call

The messages follow the house register, and each one has to be true at every
call site (intent constraint).

| site | call | message (stderr) |
|---|---|---|
| `check_disks` `:912` | `readlink -f "$path"` | `nixarchy-install: could not resolve $path. Nothing further was formatted; start again.` |
| `check_disks` `:918-921` | four `lsblk` reads, one guard | `nixarchy-install: lsblk could not read the WWN, serial, size or model of $real. Nothing further was formatted; start again.` |
| `check_free_partitions` `:1871` | `readlink -f "$device"` | `nixarchy-install: could not resolve $device.` + L2 |
| `check_free_partitions` `:1873` | `readlink -f "$part"` | `nixarchy-install: could not resolve $part.` + L2 |
| new, step 2 | `[ -b "$real" ]` | `nixarchy-install: $part does not point at a block device ($real).` + L2 |
| `check_free_partitions` `:1874` | `lsblk -nro PKNAME` | `nixarchy-install: lsblk could not read the parent disk of $real.` + L2 |
| `partition_free_space` `:1863` | `wipefs -a` | `nixarchy-install: wipefs could not clear $free_esp_real and $free_root_real (exit N).` + L2 |
| `format_disk` `:1969-1972` | LUKS key write | `nixarchy-install: could not write the LUKS key file. Nothing was formatted.` |

- **L2** is `:1877`'s existing second line: "Partition entries may exist and
  signatures may have been cleared. Inspect before retrying."
  - It is true at both `check_free_partitions` call sites (`:1848`, `:1965`).
  - It is true after a failed two-device `wipefs`, which may have cleared the
    first device before failing on the second. The draft's "The partitions
    exist" could be untrue there, so L2 replaces it (Codex).
- `check_disks` keeps "Nothing further was formatted", which is true at all
  of its call sites: `:1816` and `:1884` before sgdisk, `:1870` and `:1963`
  after it, and `install_attempts`' retries (agy).
- The key write runs after `:1963-1965` and before disko's run (`:1974`), so
  "Nothing was formatted" is true in both modes. The draft's claim that the
  earlier lines already report the partitions was wrong: at this point
  nothing has printed a refusal (agy). In free mode, the partitions created
  by sgdisk are on the disk, unformatted, and the message does not say
  otherwise.
- `wipefs` prints its own error as well. The new line names the call and its
  exit status, which wipefs's own output does not.

### 6. Checks that can fail: `tests/installer-disk-identity.nix`

This is the existing stubbed `runCommand`. It sources these functions from
`installer/install.sh` and runs in seconds.

**The re-read model** stands in for udev and the clock. It follows what the
probe saw: links from an earlier cycle are present, and a late cycle removes
them while nobody is settling.

- `esp` and `root` are fixture files standing in for the two links, present
  when sgdisk returns. The `sgdisk` stub sets `late=1`: one cycle still to
  come.
- **`sleep`** with `late=1` deletes both files and sets `late=0, due=2`. The
  late cycle's removal has landed, and its re-add needs two more settles.
- **`udevadm settle`** decrements `due` when it is above 0. When `due`
  reaches 0, it re-creates both files.
- **A wrapper around the real `check_free_partitions`** asserts at its first
  call that `late=0`, `due=0` and both files exist, then calls the real
  function.

Each variant traced through the model:

| loop | trace | wrapper sees |
|---|---|---|
| today's | `[ -b ]` passes at once | `late=1`: **red** |
| settle once, no pause | settle, `[ -b ]` passes | `late=1`: **red** |
| step 1 without the second `[ -b ]` pair | settle, pass, `sleep` (files deleted, `due=2`), settle (`due=1`), exit | files missing: **red** |
| step 1 | as above, then the second `[ -b ]` fails. The body's `sleep 0.5` does nothing, and the next settle (`due=0`) re-creates the files. Then pass, `sleep 1` (`late=0`, no-op), settle, pass | all clear: **green** |

The plan carries the stub text, and §1 breaks 1-3 below prove each red.

**Existing fixtures** (agy):

- `check_free_partitions.sh` is sourced after the same `sed` that
  `partition_free_space.sh` gets (`:231`): `[ -b ` becomes `[ -e `, and the
  stubbed `readlink` maps the links to `$PWD/esp` and `$PWD/root`.
- `touch esp root` moves above the first direct call (`:227`), so the
  foreign-parent case still fails for its own reason.
- The `lsblk PKNAME` stub keys on the new paths.
- `udevadm` and `sleep` are stubbed for the whole file.
- **Every message:** one case per row of step 5's table. The call is made to
  fail, and the case asserts exit 1 and a `grep -F` for the call, its target,
  and for `wipefs` its `(exit N)` (agy).
- **wipefs targets:** a case asserting `wipefs` received the resolved nodes,
  not `by-partlabel` paths.
- **Post-build:** the existing "post-build parent refusal prevents disko" case
  stays. A new case asserts that `udevadm settle` ran before the `:1963`
  check.

### 7. `installer/AGENTS.md`

One bullet under "Things that are true and easy to get wrong": partitions
are removed and re-added more than once after sgdisk, so a by-partlabel link
seen straight afterwards can vanish. Settle first, and settle again after a
pause, before trusting a link. It points at this spec's evidence.

## Alternatives rejected

- **`flock` the disk around sgdisk.** That is systemd's block-device locking,
  which makes udevd hold off. udevd processes the disk again when the lock is
  released, so the late cycle still follows, only later.
- **Retrying inside `check_free_partitions`.** It puts a wait inside a guard
  whose job is to fail closed. One stable wait before every user, plus loud
  refusals, is simpler.
- **Dropping `partx -u`.** It is the documented fallback for a disk with a
  mounted partition (`:1828-1829`), which a real dual-boot machine may have.
  The probe does not show that partx is the late cycle.
- **Running disko with resolved nodes.** disko's layout is the user's
  `disk-config.nix` and names `by-partlabel`. Changing that is out of this
  issue's scope. Step 4's settle covers it.
- **A message per `lsblk` field.** That is four guards for one device read.
  One message names all four fields.

## Risks

- **The pause is measured, not guaranteed.** On a host far slower than the
  probe, a cycle could land after the second settle. The window is then far
  smaller than today's. Steps 2 and 5 turn it into a named refusal rather
  than a silent exit 1, and step 3 means `wipefs` cannot act on a retargeted
  link.
- **Install time.** In free-space mode the install grows by at least 1 s plus
  two settles. Whole-disk mode gains one settle, from step 4.
- **Message text matched by tests.** Only
  `tests/installer-disk-identity.nix:228` matches one of these messages ("does
  not belong to the selected disk"), and that text stays. Checked with
  `grep -rn` over `tests/`.
- **Real hardware.** NVMe `p1` names do not matter here: paths go through
  `by-partlabel`, then `readlink -f`, as today.

## Verification

1. **`checks.installer-disk-identity` passes.** §1 breaks are each shown
   failing, with `git diff` proving the break landed:
   1. restore today's loop → the re-read case fails;
   2. settle once, no pause → it fails;
   3. drop the second `[ -b ]` pair → it fails;
   4. drop the `[ -b "$real" ]` test → the missing-node case fails;
   5. pass the links to `wipefs` again → the wipefs-target case fails;
   6. drop step 4's settle → the post-build case fails;
   7. revert any one message → its case fails.
2. **The probe on the branch's own function bodies.** The probe sources the
   real `partition_free_space` loop text rather than a copy, three
   iterations, one run: 0 failed rounds expected. Today's-loop output
   (`run4.log`) is the before.
3. **VM tier, locally, before pushing** (§6 gate): `checks.free-space`,
   `checks.install`, `checks.installer-refusal`. Whole-disk mode reaches step
   4 and `check_disks`' messages.
4. **Cheap tier:** `nix fmt -- --ci`, statix, deadnix, `grep-q-pipefail`,
   `test-registration`, `installer-ui`, `installer-wizard`, and every target
   `.github/scripts/generated-checks.sh` prints that this change reaches.
5. **Not run locally:** `install-encrypted` and `install-iso-net`, which are
   nightly. The PR says so. The LUKS message is covered by the stubbed check.
6. **After merge:** `main`'s `install-check` and the next nightly. One green
   run says little about an intermittent race, which is why the probe's
   before and after is the evidence.
