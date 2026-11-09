---
status: approved
issue: 1725
spec: spec/2026-11-09-1725-free-space-silent-exit.md
coders:
  1: codex   # small, tricky shell logic in three installer functions; needs no build
  2: coder   # the fixture edit is large, but agent-run agy cannot reach /mnt/data worktrees (exits 2 at once, #1705)
  3: coder   # one AGENTS.md bullet, sent to the same coder as step 2 while its cache is warm
reviewers:
  - codex    # reads the diff natively; it found the wipefs-target gap in the spec
  - agy      # given the diff inline; it found the fixture gaps in the spec
---

# Plan: a free-space install settles after partitioning, and every exit names its call

Branch `fix/1725-free-space-silent-exit`, worktree `/mnt/data/vmtest/wt-1725`.
Intent and spec are approved; this plan carries their decisions so it can be
followed without them.

## Decisions carried from the spec

- **The race is proven** (spec, Evidence): after sgdisk, the new partitions
  are removed and re-added more than once. Today's loop tests `[ -b ]` before
  it settles, so it can pass on links from an earlier cycle. In the probe, a
  late cycle then made `readlink -f` or `lsblk -nro PKNAME` fail in 6 of
  1,200 rounds. The new loop failed 0.
- **D1, the settle loop.** Settle, check both links, pause 1 s, settle, check
  both links again. The bound is today's `-gt 30`, which allows 31 failed
  rounds; the spec's "30" was a rounding of that (Codex). Each settle has its
  own 120 s timeout. The "never appeared" message is unchanged.
- **D2.** `check_free_partitions` refuses a link that does not resolve to a
  block device. After a link's parent check passes, it records that link's
  resolved node in the global `free_esp_real` or `free_root_real`.
- **D3.** `wipefs -a "$free_esp_real" "$free_root_real"`, not the
  `by-partlabel` links.
- **D4.** `udevadm settle` before the post-build `check_disks`, in both modes.
  **A failed settle refuses**, with its own message. It is not `|| true`:
  that would let disko run on links still changing, which is what D4
  exists to prevent (Codex).
- **D5.** Every exit gets a message, listed in step 1. Each goes to stderr
  with the `nixarchy-install:` prefix.
  - The `check_free_partitions` and `wipefs` messages are followed by L2:
    `  Partition entries may exist and signatures may have been cleared. Inspect before retrying.`
  - The `check_disks` messages end "Nothing further was formatted; start
    again."
  - "does not belong to the selected disk" keeps its exact text: the
    existing test greps for it.
- **D6.** `tests/installer-disk-identity.nix` models the late re-read
  (step 2). It has one failing case per message, a wipefs-target case and a
  post-build settle case.
- **D7.** One bullet in `installer/AGENTS.md`.

**One fixture detail is decided here, not in the spec.** The spec says the
stubbed `readlink` maps the links to `$PWD/esp` and `$PWD/root`. But
`pfs-fixture.sh` already rewrites `$esp_dev` and `$root_dev` to those same
paths. So `wipefs` would get the same arguments whether it is given the links
or the nodes, and break 5 below would stay green.

The stub therefore maps each link to a separate node, `$PWD/node-esp` and
`$PWD/node-root`, and only while the link file (`$PWD/esp`, `$PWD/root`)
exists. Otherwise it prints the path unchanged with exit 0, which is how GNU
`readlink -f` treats a missing link, as the probe measured.

## Steps

### 1. `installer/install.sh`: D1–D5 (coder: codex)

- **D1, `partition_free_space` `:1836-1846`.** Replace the loop with:

  ```bash
    # The new partitions are removed and re-added more than once after sgdisk
    # (spec/2026-11-09-1725-free-space-silent-exit.md). Settle before looking,
    # and again after a pause, so the links checked below are the last ones.
    waited=0
    until udevadm settle && [ -b "$esp_dev" ] && [ -b "$root_dev" ] &&
      sleep 1 && udevadm settle && [ -b "$esp_dev" ] && [ -b "$root_dev" ]; do
      waited=$((waited + 1))
      if [ "$waited" -gt 30 ]; then
        echo "nixarchy-install: $esp_dev and $root_dev never appeared." >&2
        echo "  The partitions were created; nothing was formatted. Reboot and look." >&2
        return 1
      fi
      sleep 0.5
    done
  ```

  Keep the existing comment block above it (`:1832-1835`).
- **D3 and D5, `wipefs` `:1863`.**

  ```bash
  wipefs -a "$free_esp_real" "$free_root_real" || {
    echo "nixarchy-install: wipefs could not clear $free_esp_real and $free_root_real (exit $?)." >&2
    echo "  Partition entries may exist and signatures may have been cleared. Inspect before retrying." >&2
    return 1
  }
  ```

  `$?` in the first command of the group is wipefs's status, as in the
  sgdisk block at `:1817-1826`. In the comment above it (`:1858-1862`),
  "these two paths" becomes "the two device nodes `check_free_partitions`
  just checked". The rest of the comment stays.
- **D2 and D5, `check_free_partitions` `:1868-1881`.** Same checks, same
  order, one refusal path. Suggested shape:

  ```bash
  check_free_partitions() {
    local part real parent selected why=
    free_esp_real='' free_root_real=''
    check_disks || return 1
    if ! selected=$(readlink -f "$device"); then
      why="could not resolve $device."
    else
      for part in /dev/disk/by-partlabel/nixarchy-{esp,root}; do
        if ! real=$(readlink -f "$part"); then
          why="could not resolve $part."
        elif ! [ -b "$real" ]; then
          why="$part does not point at a block device ($real)."
        elif ! parent=$(lsblk -nro PKNAME "$real" 2>/dev/null); then
          why="lsblk could not read the parent disk of $real."
        elif [ -z "$parent" ] || [ "$(readlink -f "/dev/$parent")" != "$selected" ]; then
          why="$part does not belong to the selected disk."
        fi
        [ -z "$why" ] || break
        case $part in *-esp) free_esp_real=$real ;; *) free_root_real=$real ;; esac
      done
    fi
    [ -n "$why" ] || return 0
    echo "nixarchy-install: $why" >&2
    echo "  Partition entries may exist and signatures may have been cleared. Inspect before retrying." >&2
    return 1
  }
  ```

  - Write the block test as `! [ -b "$real" ]`, never `[ ! -b`. The test's
    `sed 's|\[ -b |[ -e |g'` has to match it.
  - The globals are reset at the top, so a failed second call
    (`format_disk`) cannot leave the first call's nodes behind.
  - Keep the two-line comment above the function.
- **D5, `check_disks` `:912`.**

  ```bash
  real=$(readlink -f "$path") || {
    echo "nixarchy-install: could not resolve $path. Nothing further was formatted; start again." >&2
    return 1
  }
  ```

- **D5, `check_disks` `:918-921`.** The four reads go under one guard:

  ```bash
  { wwn=$(lsblk -dnro WWN "$real" 2>/dev/null) &&
    serial=$(lsblk -dnro SERIAL "$real" 2>/dev/null) &&
    size=$(lsblk -bdnro SIZE "$real" 2>/dev/null) &&
    model=$(lsblk -dnro MODEL "$real" 2>/dev/null); } || {
    echo "nixarchy-install: lsblk could not read the WWN, serial, size or model of $real. Nothing further was formatted; start again." >&2
    return 1
  }
  ```

- **D4, `format_disk` `:1963`.** Directly before
  `check_disks || { rm -f …; return 1; }`, in both modes:

  ```bash
  # wipefs's close and the build leave udev events queued; check settled links.
  udevadm settle || {
    rm -f /tmp/nixarchy-luks.key
    echo "nixarchy-install: udevadm settle did not finish after the disko build. Nothing was formatted; start again." >&2
    return 1
  }
  ```
- **D5, LUKS key write `:1969-1972`.** Inside the existing `|| { … }`, before
  `return 1`:

  ```bash
  echo "nixarchy-install: could not write the LUKS key file. Nothing was formatted." >&2
  ```

- **Not in this step:** commits, builds, and anything outside these three
  functions and `format_disk`. Codex's sandbox cannot reach the nix daemon,
  so it should not try to build.
- **Verify:**

  ```bash
  bash -n installer/install.sh
  git diff --stat   # installer/install.sh only
  ```

  The lead then runs step 2's check.
- **Traps:**
  - this code runs inside `main()`'s `|| rc=$?` chain, where errexit is off,
    so every failure needs its own `|| { …; return 1; }` (`:1811-1815`);
  - `checks.grep-q-pipefail`: no `| grep -q`.

### 2. `tests/installer-disk-identity.nix`: D6 (coder: coder)

`test.sh` is already a heredoc inside the `''` string. Add no second heredoc
(CLAUDE.md §5), and write `${` as `''${`.

- **Model stubs, at the top of `test.sh`** near the other stubs (`:19-22`).
  `late` and `due` start at 0, so the stubs do nothing for the existing
  whole-disk cases:

  ```bash
  late=0 due=0
  udevadm() {
    [ "$1" = settle ] || return 0
    echo settle >> events
    if [ "$due" -gt 0 ]; then due=$((due - 1)); [ "$due" -gt 0 ] || touch esp root; fi
  }
  sleep() { if [ "$late" = 1 ]; then rm -f esp root; late=0; due=2; fi; }
  ```

- **Free-space fixture, at `:206-233`.** Before the first direct
  `check_free_partitions` call (`:227`):
  - re-source `check_free_partitions.sh` through
    `sed 's|\[ -b |[ -e |g'`. The path substitutions do not match its
    brace-form loop, and the stubbed `readlink` handles the links;
  - `touch esp root node-esp node-root` (moved up from `:233`).

  Replace the stubbed `readlink` at `:211-216` with:

  ```bash
  readlink() {
    case "$2" in
      /dev/disk/by-partlabel/nixarchy-esp) if [ -e esp ]; then echo "$PWD/node-esp"; else echo "$2"; fi ;;
      /dev/disk/by-partlabel/nixarchy-root) if [ -e root ]; then echo "$PWD/node-root"; else echo "$2"; fi ;;
      *) echo "$2" ;;
    esac
  }
  ```

  The `lsblk PKNAME` stub (`:219-224`) keys on `$PWD/node-esp` and
  `$PWD/node-root`.
- **The `sgdisk` stub** (`:237`) also sets `late=1`.
- **The re-read wrapper.** After `pfs-fixture.sh` is sourced:
  - rename the real function:
    `eval "$(declare -f check_free_partitions | sed '1s/check_free_partitions/real_check_free_partitions/')"`;
  - define a `check_free_partitions` that calls
    `failed "check_free_partitions ran before the late re-read settled"`
    unless `late=0`, `due=0`, and `esp` and `root` both exist;
  - after that assertion, the wrapper resets the model
    (`late=0 due=0; touch esp root`), then calls
    `real_check_free_partitions`. Without the reset, a break that leaves
    `late=1` makes every later case fail too, and the break's output no longer
    names the one case it should (agy).

  Every existing `partition_free_space` case then also runs the model. The
  `ok free-space …` line stays, with a new `ok` line for the re-read.
- **Message cases**, one per row.
  - Each runs the call with `>out 2>err` and asserts exit 1.
  - Each asserts that `grep -F` finds the whole line, prefix included, in
    `err`. So a message moved to stdout or stripped of its `nixarchy-install:`
    prefix turns the case red (Codex).
  - Where the row says + L2, the case also greps `err` for L2.

  | # | how it is made to fail | line in `err` |
  |---|---|---|
  | a | `readlink` returns 1 for `/dev/a`, `check_disks` | `nixarchy-install: could not resolve /dev/a. Nothing further was formatted; start again.` |
  | b | the `lsblk` stub returns 1 for `MODEL`, the last of the four, so the chain is shown reaching it (agy). `TYPE` stays `disk` | `nixarchy-install: lsblk could not read the WWN, serial, size or model of /dev/a. Nothing further was formatted; start again.` |
  | c | `device=/dev/by-id-a`; `readlink` returns 1 for it alone, so `check_disks` on `/dev/a` passes | `nixarchy-install: could not resolve /dev/by-id-a.` + L2 |
  | d | `readlink` returns 1 for `/dev/disk/by-partlabel/nixarchy-root` | `nixarchy-install: could not resolve /dev/disk/by-partlabel/nixarchy-root.` + L2 |
  | e | `rm -f node-root`: the link resolves, but to nothing, and the `PKNAME` stub would still answer `a` | `nixarchy-install: /dev/disk/by-partlabel/nixarchy-root does not point at a block device ($PWD/node-root).` + L2 |
  | f | the `PKNAME` stub returns 1 | `nixarchy-install: lsblk could not read the parent disk of $PWD/node-esp.` + L2 |
  | g | the `wipefs` stub returns 3 | `nixarchy-install: wipefs could not clear $PWD/node-esp and $PWD/node-root (exit 3).` + L2 |
  | h | `mkdir /tmp/nixarchy-luks.key`; the `nix eval` stub prints `true`; `luks_passphrase=secret`; `disk_mode=whole`; `rmdir` afterwards | `nixarchy-install: could not write the LUKS key file. Nothing was formatted.`, and `disko-ran` absent |
  | i | the `udevadm` stub returns 1 once `events` holds `build` | `nixarchy-install: udevadm settle did not finish after the disko build. Nothing was formatted; start again.`, and `disko-ran` absent |

  - **Why case e removes the node, not the link (agy).** Removing the link
    leaves the unchanged `by-partlabel` path. The `PKNAME` stub does not know
    that path, so with the block test dropped the case still refuses, as
    "does not belong". Removing the node makes the dropped test an
    acceptance (exit 0), which the exit-status assertion catches.
  - Each case restores the stubs and fixture files it changed.
- **wipefs-target case.** The `wipefs` stub writes `"$*"` to `wipefs-args`.
  Assert it equals `-a $PWD/node-esp $PWD/node-root`.
- **Post-build settle case**, beside "post-build parent refusal prevents
  disko":
  - `: > events`;
  - the `nix` build stub appends `build` to `events`;
  - wrap `check_disks` (eval-rename, as above) to append `check`, then call
    the real one;
  - run `format_disk` with `disk_mode=whole`;
  - assert the three lines from `build` onward
    (`sed -n '/^build$/,$p' events`) are `build`, `settle`, `check`. Do not
    compare the whole file: `check_disks` also runs at `:1884`, before the
    build (agy).
- **Verify:**

  ```bash
  flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.installer-disk-identity --print-build-logs
  ```

  Expected: every `ok` line, and no `FAILED`.
- **Traps:**
  - commit before building (`installer/mkFlake.nix` needs a committed tree,
    §5);
  - a hook may run `nixpkgs-fmt`, so run `nix fmt` and read
    `git diff --stat` (§5);
  - no `| grep -q`.

**Deviations found while implementing:**

- **`tests/installer-store-space.nix` gains a `udevadm` stub.** It sources
  the real `format_disk` with no `udevadm` on its path, so D4's settle
  refused there.
- **The globals are reset as `free_esp_real='' free_root_real=''`.** The
  form without quotes fails shellcheck SC1007 in the installer package.
- **`failed` writes to fd 3.** A failure raised inside a call redirected to
  `msg` (the re-read wrapper) then still reaches the log.

### 3. `installer/AGENTS.md`: D7 (coder: coder, same agent)

One bullet at the end of "Things that are true and easy to get wrong"
(`:40`):

> **A by-partlabel link seen straight after sgdisk can vanish.** The kernel
> removes and re-adds the new partitions more than once, and the last cycle
> can land after the links first appear. Settle, pause, settle again, and
> re-check before trusting a link (#1725; evidence in
> `spec/2026-11-09-1725-free-space-silent-exit.md`).

**Verify:** `git diff installer/AGENTS.md` shows one bullet.

### 4. Break proofs (lead)

Commit a known-good baseline first. Revert each break with
`git checkout HEAD -- <file>`, never `git checkout -- <file>` (§5). Prove
each break landed with `git diff` before reading the result. Each must make
`installer-disk-identity` print `FAILED`:

1. today's loop restored → the re-read case;
2. settle once, no pause → the re-read case;
3. the second `[ -b ]` pair dropped → the re-read case;
4. `! [ -b "$real" ]` dropped → case e;
5. `wipefs -a "$esp_dev" "$root_dev"` restored → the wipefs-target case;
6. D4's settle dropped → the post-build settle case;
7. one message reverted (case f's) → case f;
8. D4's refusal replaced by `|| true` → case i.

Each failing output goes in the PR.

### 5. Probe on the branch's own loop (lead)

The probe runs an inline snippet against `/dev/vdb`, not the whole function.
`partition_free_space` needs `free_space_possible`, `check_disks` and the
wizard's variables, so it cannot run alone (agy).

- Replace the probe's copy of the loop with the loop from the branch's
  `installer/install.sh`. Extract the function first, then the loop inside
  it:

  ```bash
  sed -n '/^partition_free_space()/,/^}/p' installer/install.sh | sed -n '/^  waited=0$/,/^  done$/p'
  ```

- Set `esp_dev` and `root_dev` to the two `by-partlabel` paths.
- Prove the extract is non-empty, and contains `sleep 1 && udevadm settle`,
  before booting.
- Run three iterations once, in a VM slot (step 6's gate).

Expected: 0 failed rounds of 1,200. `run4.log` is the before.

### 6. Local checks before push (lead, §6 tiers)

- **Cheap, any time**, one at a time under the codex-build lock:
  - `nix fmt -- --ci`, statix, deadnix;
  - `grep-q-pipefail`, `test-registration`, `installer-ui`,
    `installer-wizard`;
  - every reachable target `.github/scripts/generated-checks.sh` prints.
- **VM tier**, when no self-hosted runner is busy
  (`gh api repos/olafkfreund/nixarchy/actions/runners -q '[.runners[]|select(.busy)]|length'`
  prints `0`) and no p620 system build is running:
  - `free-space`, `install`, `installer-refusal`;
  - evaluate the `drvPath` first, then `nix build "$drv^*"` (§5).
- **Not run locally:** `install-encrypted` and `install-iso-net` (nightly).
  The PR says so.

### 7. Pull request (lead)

- Push the branch. The PR links the intent, spec and plan.
- The PR body carries:
  - which steps codex and the coder did, and any fallback;
  - the break outputs;
  - the probe's before and after;
  - what was not run.
- Comment `@codex review`, and verify its findings. The Opus review and the
  `reviewers:` reviews run on `git diff origin/main` before the push.
- Merge with `gh pr merge --auto --merge --delete-branch`: this branch holds
  several commits, artifacts included.
- Post on the agent bus: a by-partlabel link seen straight after sgdisk can
  vanish.

## Tests

| check | expected |
|---|---|
| `installer-disk-identity` | green, and red under each of step 4's eight breaks |
| probe (step 5) | 0 of 1,200 rounds fail |
| `free-space`, `install`, `installer-refusal` | green locally |
| cheap tier | green |

## Rollback

Revert the merge commit. Only the installer, one check and one doc bullet
change. No option, no layout and no on-disk format changes, so an installed
machine is unaffected.
