---
status: approved
issue: 1089
spec: spec/2026-09-30-1089-installer-disk-safety.md
---

# Plan: Verify installer disks and cached images at use

The installer must preserve the identity of every disk the user chose or
accepted, then compare it just before each destructive stage. A disk with
neither WWN nor serial is refused. Free-space partition labels must resolve
back to that disk before `wipefs` and disko. A retry never resets the original
fingerprint. Phase guards return failure to the installer's existing failure
screen. The passphrase file exists only if the **evaluated disko layout** has
a LUKS `passwordFile` pointing to `/tmp/nixarchy-luks.key`, and only while
disko runs. `#try` downloads a fresh release checksum on every invocation,
verifies even cached ISOs, and replaces a corrupt copy only with verified
bytes. The offline finish screen names `omarchy` only if the baked reference
system was actually copied; built paths name the requested username.

The #1111 `wipefs` failure propagation and `--host` syntax validation are
already correct; retain and test them. Other #1098 installer-validation items
belong to a separate follow-up. There is currently no VM whose purpose is to
test a serial-less disk; the cheap identity check supplies that negative case.
An answers file that names only `/dev/sdX` cannot prove what disk its author
meant before this process began. The comparisons protect the identity first
observed during this run, not an earlier one.

## Steps

1. `tests/install.nix:464`, `tests/free-space.nix:472`,
   `tests/installer-refusal.nix:104,134`, `tests/install-encrypted.nix:352`,
   `tests/installer-wizard.nix:41-49`, `installer/vm.nix:145`: keep disk sizes,
   ordering, and `empty0.qcow2` names; express each selected/accepted blank
   target as an `emptyDiskImages` entry with a fixed, distinct test serial in
   `driveConfig.deviceExtraOpts.serial` (the pinned VM module supports it).
   `tests/install-iso.nix:382,480`, `tests/install-iso-net.nix:355,419`,
   `tests/reinstall-vm.nix:307,384`, `installer/try.sh:537-545`,
   `installer/try-nixarchy.sh:161`, and the virtio branch of
   `tests/install-matrix.py:357`: attach a serial to the **target** disk's
   virtio device. In `install-iso`, `install-iso-net`, and `reinstall-vm`, turn
   **both** the installer target and the answers drive into `-drive if=none`
   with separate IDs and explicit `-device virtio-blk-pci,drive=...` entries:
   attach the target first with its serial and the answers drive second
   without that serial, preserving target `/dev/vda` and answers `/dev/vdb`.
   Their subsequent installed-target boot also gets the explicit target
   device and serial. For other raw launchers, use an explicit
   `-drive if=none,id=...` plus `-device virtio-blk-pci,drive=...,serial=...`
   where `if=virtio` cannot set the device property. Retain the NVMe
   branch's `serial=nixarchytest` at `tests/install-matrix.py:354-355`.
   `tests/try-nixarchy.nix`: capture the no-Nix launcher's QEMU argv with its
   existing stub. `tests/try-preflight.nix`: source `installer/try.sh` with
   `NIXARCHY_TRY_SOURCED=1`, set `QEMU` to an argv-logging executable, stub
   `detect_kvm`, `check_ram`, and `check_disk`, provide a fixture disk and
   OVMF vars file, then run `main --boot --vnc` in a subshell (it `exec`s
   QEMU); assert the logged target device argument contains the serial. A
   source grep or a probe that exits before `main` cannot see those args
   `installer/try.sh:537-545` has separate `--boot` and install launches;
   construct one target-drive device string with the serial and use it in
   both branches. Extend the stub to run the install branch with a fixture
   ISO and capture that QEMU argv too. Break-proof the shared construction
   by copying `installer/try.sh` aside, removing the serial from the install
   launch alone, and showing the install-argv assertion red; restore with
   `cp` and show both branches green.
   -> verify by
   `flock /mnt/data/vmtest/codex-build.lock nix build
   .#checks.x86_64-linux.try-nixarchy --print-build-logs` and then the same
   command for `try-preflight`, one invocation at a time, and by the listed
   install VM checks in CI after all installer steps. Break proof: copy each launcher aside
   under `/mnt/data/vmtest/`, remove its target serial, show the corresponding
   cheap assertion red, restore with `cp`, then show it green. The matrix's
   virtio/NVMe paths and installer VM launch are manual/CI checks, not local
   VM runs. After the `.nix` edits run `nix fmt`, inspect `git diff --stat`,
   then `nix fmt -- --ci`.

2. `installer/install.sh:774-808,1215-1284,1440-1471,1612-1673,3015-3095`:
   record both nonempty WWN and serial for the resolved whole disk at wizard
   selection or after answers validation, and for **every** evaluated
   repository-defined disk during `confirm_repo_disks`. Refuse when neither
   exists, with an actionable message. Keep the recorded identities fixed
   through `install_attempts` retries. Compare resolved paths and the recorded
   identifiers before the first destructive action and again after the disko
   build, immediately before disko execution. A missing, unreadable, or
   changed identity returns 1 from the phase without refreshing the baseline;
   preserve the confirmation, boot-medium refusal, and existing free-region
   remeasurement. `tests/installer-disk-identity.nix` and `flake.nix`: add a
   cheap check against the installer functions with stubs for `lsblk`, `readlink`,
   `nix`, and disko. Cover wizard, answers, multiple repo disks, no identifiers,
   same-sized replacement, swap during build, unchanged retry baseline, and
   no destructive command after refusal -> verify by
   `flock /mnt/data/vmtest/codex-build.lock nix build
   .#checks.x86_64-linux.installer-disk-identity --print-build-logs`.
   Break proofs: copy `installer/install.sh` aside outside the worktree,
   then independently (a) allow an identity with neither WWN nor serial,
   (b) remove the pre-write comparison, (c) remove the post-build comparison,
   (d) reset the saved fingerprint on retry, and (e) validate only the first
   repo disk while a second changes. Confirm each edit landed with `git diff`,
   capture that case's distinct red line, restore with `cp`, and capture
   green before the next break. Add the new test to git before Nix evaluates the
   flake. Run `nix fmt`, inspect `git diff --stat`, and run `nix fmt -- --ci`.

3. `installer/install.sh:1519-1609,1640-1673` and
   `tests/installer-disk-identity.nix`: in free-space mode, verify both
   `/dev/disk/by-partlabel/nixarchy-esp` and `-root` resolve to partitions
   whose parent is the originally recorded disk after udev settle and before
   `wipefs`; repeat after the disko build and before running it. Keep
   `partition_free_space || return 1`: `wipefs` is the function's last command
   and its failure must stop disko. Return 1 with a truthful partial-write
   message, leaving the existing failure screen and retry available -> verify
   by `checks.installer-disk-identity` and `checks.installer-store-space` under
   the shared build lock. Break proofs: copy `installer/install.sh` aside,
   remove each parent check in turn and show a foreign-partition fixture makes
   the identity check red; restore with `cp` and show green. Separately append
   `|| true` to `wipefs`, show the store-space case red, then restore and show
   green. Never use `git checkout` for restoration.

4. `installer/install.sh:1639-1641,1643-1673,3055-3058` and
   `tests/installer-store-space.nix`: before partition writes, evaluate the
   chosen host's `config.disko.devices`; inspect LUKS nodes' `passwordFile`
   values for `/tmp/nixarchy-luks.key`. Do not use the `encrypt` answer as the
   decision: an existing `--from` host skips `ask_encrypt`, and its layout can
   differ. Put this evaluation and any missing-passphrase refusal **before**
   the `disk_mode=free` call to `partition_free_space` at `:1639-1641`, not
   just before writing the key. Refuse with `return 1` before writes if the
   evaluated layout needs the key but no passphrase is available. Build disko first, then write the
   key with `umask 077` immediately before executing disko only when the
   layout needs it. Remove it on all normal and error paths, retaining the
   interrupt trap; a failed layout evaluation also refuses before writes.
   Add fixtures for plain layout, keyed LUKS, divergent `--from`, missing
   passphrase, build failure, disko failure, and success; assert key timing and
   absence afterward -> verify by `checks.installer-store-space` under the
   lock. Break proofs: copy `installer/install.sh` aside, restore the old
   unconditional early key write and show the plain/build cases red; replace
   the evaluated-layout decision with `encrypt` and show the divergent
   `--from` case red; restore with `cp` and show green.

5. `installer/try.sh:225-288` and `tests/try-preflight.nix`: download the
   current release's `SHA256SUMS` **fresh every time** into a temporary file
   outside `CACHE_DIR`, clean it up on every return, and require the exact ISO
   entry. Hash a cached ISO before returning it. If corrupt, delete it,
   download the release parts, and verify the replacement against the fresh
   checksum. Refuse when metadata, fresh checksum, matching entry, download,
   or verification is unavailable; never use a stale cached checksum. Keep
   `.part` assembly and the existing verification for new downloads.
   Stub API, checksum and downloads for valid cache, corrupt cache/recovery,
   missing checksum, failed replacement, and an old cached sums file with a
   failed fresh fetch -> verify by `checks.try-preflight` under the lock.
   Break proofs: copy `installer/try.sh` aside, restore early cached-ISO
   return and show corrupt-cache case red; separately fall back to cached
   sums and show fresh-fetch-failure case red; restore with `cp` and show green.

6. `installer/install.sh:2607-2715,3005`,
   `installer/lib/dashboard.sh:201-210`, and
   `tests/installer-baked-guard.nix`: track whether `run_install` actually
   selected and installed the valid baked reference system. Pass `omarchy` to
   the finish screen only on that copied path and explain that the requested
   account appears after the first online rebuild. On fallback build,
   free-space, and `--from`, keep the requested username. Do not alter the
   installed system or create another account -> verify by
   `checks.installer-baked-guard` under the lock. Break proof: copy product
   files aside under `/mnt/data/vmtest/`, restore the old unconditional
   requested-username finish call, show the copied-system case red, restore
   with `cp`, and show green.

## Tests

*Deviation (implementation):* `installer-disk-identity` reads the tracked
`installer/install.sh` source, as the existing cheap installer checks do.
Depending on the built `packages.install` requires a committed source tree
through `installer/mkFlake.nix`, which makes the mandated cp-aside red proofs
unevaluable. The separate installer package build runs after the Step 2
commit; the function check still varies with every source edit.

- At this draft gate: documentation diff only, no builds or VM runs. During
  implementation, stage new files before building because the flake cannot
  see untracked paths. **Before every local Nix build, including every red
  proof, run exactly**
  `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
  **and build only if it prints `0`**; wait otherwise, and stop on a query
  error. Each `nix build` above then takes the shared
  `/mnt/data/vmtest/codex-build.lock` and runs one at a time. Use
  `--print-build-logs` without a pipeline that could hide exit status. Save
  break-proof logs outside the worktree and paste their key red lines into
  the PR, not log files.
- Cheap green checks: `installer-disk-identity`, `installer-store-space`,
  `installer-from-repo`, `installer-baked-guard`, `try-preflight`,
  `try-nixarchy`, and `installer-answers` if its answer flow changes. Each
  new assertion must be shown red by breaking the product, then green after
  restoration; verify the break landed in `git diff` before trusting a green.
- PR CI: `install`, `free-space`, `installer-refusal`, and
  `installer-wizard`. They must reach their original assertions, not simply
  fail at the new identity guard. `installer-refusal` already asserts at
  `tests/installer-refusal.nix:178-184` that the refusal names the unreachable
  Cachix substituter; an early identity refusal cannot satisfy it.
- Nightly only: `install-encrypted`, `install-iso`, `install-iso-net`, and
  `reinstall-vm`. Their target-serial changes cannot be proven by PR CI;
  verify those results after merge. Manual when hardware permits: `installer/vm.nix`,
  `#try`, no-Nix `try-nixarchy.sh`, and both virtio/NVMe
  `tests/install-matrix.py` paths. No local VM or `checks.options` run.
- After any `.nix` edit run `nix fmt` and inspect `git diff --stat`; final
  gates are `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .`. Scan the diff for added
  `producer | grep -q` and writes to `omarchy/shell.json`.

## Rollback

Revert the implementation commits in reverse plan-step order, retaining the
approved intent/spec/plan history. Do not reuse a disk after an identity
refusal until the user reselects it in a new installer run. No deployed
machine changes merely by reverting the release-image or finish-screen code.
