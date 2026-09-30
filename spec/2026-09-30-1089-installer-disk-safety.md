---
status: approved
issue: 1089
intent: intent/2026-09-30-1089-installer-disk-safety.md
---

# Spec: Verify disk identity and cached images at use

## Design

1. **Disk identity.** `installer/install.sh:774-808` retains the physical
   identity of the disk chosen by the wizard; `:1215-1284` does so for an
   answers-file disk immediately after validation. Read both WWN and serial
   from `lsblk` for the resolved whole device. Keep every nonempty identifier
   and require at least one. If both are absent, refuse with a message to
   choose a disk whose identity can be checked. For a repository-defined
   machine, `confirm_repo_disks` (`:1440-1471`) records the same identity for
   every disk it evaluates, while still showing the disks to the user and
   refusing the boot medium. An answers file remains its existing consent.
   Freeze these original fingerprints when the install attempt begins;
   `install_attempts` can retry after a phase failure (`:3015-3095`), but a
   retry must compare against the original identities, never re-baseline a
   replaced device.
   Before `format_disk` can change the disk (`:1626-1640`), resolve every
   recorded path and compare its current identity with the recorded one;
   refuse on a missing, changed, or unreadable identity. In free-space mode,
   retain the existing free-region remeasurement (`:1519-1538`) and check
   identity before its first `sgdisk` write. The free-space layout addresses
   `/dev/disk/by-partlabel/nixarchy-{esp,root}`
   (`installer/disk-config.nix:186-210`): after `sgdisk` and udev settle,
   verify that both resolved partitions belong to the recorded parent disk
   before `wipefs` touches either one (`installer/install.sh:1589-1609`).
   Check identity **and partition parentage** again after the disko script
   has built and immediately before executing it (`:1648-1673`), since the
   build may take a long time. A phase refusal uses `return 1`, not `exit`,
   so `install_attempts` keeps its failure screen and retry path; the message
   names the disk and any partitioning already completed. Preserve the #1111
   `partition_free_space || return 1` check (`:1640`): a failing `wipefs`
   already propagates from the final command of `partition_free_space`
   (`:1609`).

2. **Temporary LUKS key.** The generated layout names
   `/tmp/nixarchy-luks.key` only on its LUKS node
   (`installer/disk-config.nix:75-93`), but `--from` an existing host skips
   `ask_encrypt` and uses the repository's own layout
   (`installer/install.sh:2934-2942`, `:1648-1664`). The `encrypt` answer
   therefore cannot decide whether that script needs the key. Before any
   partition write, evaluate the selected host's `config.disko.devices` and
   inspect its LUKS nodes' `passwordFile` values; decide whether any equals
   `/tmp/nixarchy-luks.key`. Refuse with `return 1` before writes if that
   evaluated layout needs this file and `luks_passphrase` is empty. Build the
   disko script first, then create the file with restrictive permissions only
   when the evaluated layout needs it, immediately before executing disko
   (`installer/install.sh:1643-1673`). Remove it on all success and failure
   paths, retaining the interrupt cleanup (`:3055-3058`). This covers a
   repository host whose encryption differs from the answers-file value.
   A build failure cannot leave a new key file because none was created yet;
   a layout without this passwordFile creates none even if a passphrase was
   supplied.

3. **Cached release ISO.** In `installer/try.sh:225-288`, download the current
   release's `SHA256SUMS` fresh on **every** invocation into a temporary file
   outside `CACHE_DIR`; never fall back to an older cached checksum file.
   Require an exact checksum entry for the selected ISO before using any
   cached file. Verify the cached file against that
   checksum on every invocation. If it differs, delete it, download the
   release parts again, and verify the replacement before returning its path.
   If release metadata, the fresh checksum file, the matching entry, the
   download, or replacement verification is unavailable, return an error and
   do not boot an image. Remove the temporary checksum file on every return.
   Keep the existing `.part` download and checksum behavior for a new ISO
   (`:252-288`), using the same fresh checksum bytes.

4. **Identifiable test disks.** The real-install VM targets are currently
   serial-less virtio disks. Give each target a fixed test-only serial in
   `tests/install.nix:464`, `tests/free-space.nix:472`,
   `tests/installer-refusal.nix:104,134`,
   `tests/install-encrypted.nix:352`, and `installer/vm.nix:145`. The pinned
   NixOS VM module supports an `emptyDiskImages` entry with `size` and
   `driveConfig.deviceExtraOpts.serial`, so retain the same sizes, disk order,
   and `empty0.qcow2` paths. The interactive dry-run fixture also selects
   `/dev/vdd` from `tests/installer-wizard.nix:41-49`; give that third empty
   disk a serial so its wizard still reaches the dry-run assertion. Give the
   target disk a serial on each raw QEMU
   `-drive`/`virtio-blk-pci` path in `tests/install-iso.nix:382,480`,
   `tests/install-iso-net.nix:355,419`, `tests/reinstall-vm.nix:307,384`,
   `installer/try.sh:537-545`, and the user-facing no-Nix launcher
   `installer/try-nixarchy.sh:161`. The virtio branch in the manual published
   ISO matrix (`tests/install-matrix.py:357`) also needs a target serial;
   its NVMe branch already supplies `serial=nixarchytest` (`:354-355`).
   Use an explicit target `virtio-blk-pci` device where a raw `-drive
   if=virtio` cannot set the device's serial. Do not assign the target's serial to the
   answers-file drive. The current VM suite has **no deliberate no-serial
   disk refusal case**; the new cheap identity check below supplies that
   negative case. The positive install checks must still reach their original
   assertions rather than pass through an early identity refusal.

5. **Truthful first login.** `run_install` in `installer/install.sh:2607-2715`
   records whether it actually handed the valid baked reference system to
   `nixos-install`, rather than inferring this from the offline marker alone:
   free-space and `--from` installs, and a missing baked closure, build their
   own system. On successful completion, pass `omarchy` to `ui_finished`
   (`installer/install.sh:3005`, `installer/lib/dashboard.sh:201-210`) only
   when the reference system was copied. Say that the requested account will
   become available after the first online rebuild. Otherwise name the
   requested username as today. Do not change which system is installed or
   create another account during installation.

## Alternatives rejected

- Trusting `/dev/sdX`, matching disk size, or only repeating the free-space
  measurement: each can still describe a different physical disk after a
  device change.
- Proceeding when both WWN and serial are absent: the owner chose to fail
  closed before writes; the installer cannot establish the chosen disk's
  identity.
- Checking identity only before preflight: a long preflight or disko build
  leaves a window in which the target can change.
- Trusting the by-partlabel symlinks without checking their parent disk: a
  stale or duplicate label could route `wipefs` or disko to somebody else's
  partition even while the selected disk's fingerprint still matches.
- Basing the key-file decision on `encrypt`: an existing `--from` host uses
  its evaluated disko layout, which may disagree with that answer.
- Reusing a cached ISO because it verified on a previous run, or trusting a
  stale local `SHA256SUMS`: neither proves the bytes about to boot.
- Always saying `omarchy` on an offline image: the baked closure can be
  unavailable, and free-space or `--from` installs build another system.
- Folding the remaining #1098 installer-validation items into this change:
  they live in different parsing, network, and hardware-generation functions.
  The owner reserved them for a separate follow-up. The #1089 `wipefs` and
  #1098 `--host` claims were already fixed by #1111.

## Risks

- Some USB devices may expose neither WWN nor serial. The deliberate refusal
  needs a clear message. All positive VM installer targets must carry the
  fixed serials above; otherwise they fail at this new guard before their
  intended assertions.
- A serial or WWN check narrows the device-swap window but cannot make a
  hot-swappable device operation atomic. The checks run immediately before
  each destructive stage. An answers file that names only `/dev/sdX` also
  cannot prove which physical disk its author intended before this process
  began; the installer can establish and preserve only the identity it first
  observes during the run.
- Re-verifying a cached ISO requires the current release checksum to be
  reachable on every use. `#try` already requires the release API; cached
  reuse now also needs the checksum download, by the owner's decision.
- Evaluating a `--from` host's disko structure before formatting can fail on
  a broken third-party flake. That failure must refuse before writes, naming
  the configuration error rather than trying disko with a guessed key state.
- The finish text must follow the *actual* copied/built branch; using only the
  presence of `/etc/nixarchy-reference-*` would misreport fallback builds.

## Verification

- Add a cheap `checks.installer-disk-identity` that runs the built installer
  functions with stubbed `lsblk`, `readlink`, `nix`, and disko. It covers the
  wizard/answers disk, all repository-defined disks, missing WWN and serial,
  a replaced device with the same size and free region, a swap during disko
  build, a retry against the original fingerprint, and no destructive
  command after refusal. Stub by-partlabel paths pointing to another disk
  before `wipefs` and after the build: both must refuse without wiping or
  running disko. Extend `tests/installer-store-space.nix`'s format fixture
  with evaluated-layout fixtures for a plain disk, a LUKS disk using this
  key path, and a `--from` disk whose layout needs the key despite an
  `encrypt=false` answer. Assert the key is absent during build, present only
  during the applicable disko execution, removed afterward, and that a
  missing passphrase or failed `wipefs` stops before disko.
- Extend `tests/try-preflight.nix` with a stubbed release API, checksum file,
  and download. Assert valid cache reuse after checksum verification, corrupt
  cache deletion and verified replacement, and refusal when checksums or
  replacement bytes are missing. Include an older, apparently valid cached
  `SHA256SUMS` while the fresh checksum fetch fails; the cached ISO must not
  be used. Extend `tests/installer-baked-guard.nix` to
  assert the finish-screen login for actual baked copy versus fallback build,
  free-space, and `--from` paths.
- For **each** new assertion, copy its product file aside outside the worktree
  under `/mnt/data/vmtest/`, remove the relevant guard or return the old
  behavior, run the named check and capture its failing line, restore with
  `cp` (never `git checkout`), then run it green. Break disk rechecks,
  no-identity refusal, by-partlabel parent checks, LUKS key timing and
  evaluated-layout decision, fresh-checksum requirement, cache verification,
  and the copied login selection independently. Also swallow `wipefs`'s failing status in
  the product and prove its failure case goes red. Put the red output in the
  PR.
- CI must also keep `checks.install`, `checks.free-space`,
  `checks.installer-refusal`, `checks.install-encrypted`,
  `checks.install-iso`, `checks.install-iso-net`, and
  `checks.reinstall-vm`, and `checks.installer-wizard` green with their
  original assertions reached; launch `installer/vm.nix`, `#try`, the no-Nix
  `try-nixarchy.sh`, and both virtio and NVMe install-matrix paths in their
  supported manual modes when hardware permits. Do not run those VMs locally
  at the spec gate.
- Build only cheap checks under the shared lock after plan approval. Run
  `nix fmt -- --ci`, statix, deadnix, and scan the diff for added
  `producer | grep -q` and `omarchy/shell.json` writes. CI runs the VM install
  matrix; no local VM or `checks.options` is required for this spec gate.
