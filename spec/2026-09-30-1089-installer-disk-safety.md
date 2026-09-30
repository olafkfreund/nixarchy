---
status: draft
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
   Before `format_disk` can change the disk (`:1626-1640`), resolve every
   recorded path and compare its current identity with the recorded one;
   refuse on a missing, changed, or unreadable identity. In free-space mode,
   retain the existing free-region remeasurement (`:1519-1538`) and check
   identity before its first `sgdisk` write. Check again after the disko
   script has built and immediately before executing it (`:1648-1673`),
   since the build may take a long time. A refusal names the disk and says
   that nothing further was formatted. Preserve the #1111
   `partition_free_space || return 1` check (`:1640`): a failing `wipefs`
   already propagates from the final command of `partition_free_space`
   (`:1609`).

2. **Temporary LUKS key.** `installer/disk-config.nix:79-89` names
   `/tmp/nixarchy-luks.key` only for encrypted layouts. In
   `installer/install.sh:1643-1673`, build the disko script first; only when
   `encrypt=true`, create the file with restrictive permissions immediately
   before executing the script. Keep removal on success and failure, and the
   interrupt cleanup at `:3055-3058`. An unencrypted install creates no key
   file, even if an answers file contained a login password or an unused LUKS
   passphrase. A build failure cannot leave a key file because none was
   created yet.

3. **Cached release ISO.** In `installer/try.sh:225-288`, fetch the current
   release's `SHA256SUMS` and require an exact checksum entry for the selected
   ISO before using any cached file. Verify the cached file against that
   checksum on every invocation. If it differs, delete it, download the
   release parts again, and verify the replacement before returning its path.
   If release metadata, the checksum file, the matching entry, the download,
   or replacement verification is unavailable, return an error and do not
   boot an image. Keep the existing `.part` download and checksum behavior
   for a new ISO (`:252-288`).

4. **Truthful first login.** `run_install` in `installer/install.sh:2607-2715`
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
- Reusing a cached ISO because it verified on a previous run, or trusting a
  stale local `SHA256SUMS`: neither proves the bytes about to boot.
- Always saying `omarchy` on an offline image: the baked closure can be
  unavailable, and free-space or `--from` installs build another system.
- Folding the remaining #1098 installer-validation items into this change:
  they live in different parsing, network, and hardware-generation functions.
  The owner reserved them for a separate follow-up. The #1089 `wipefs` and
  #1098 `--host` claims were already fixed by #1111.

## Risks

- Some USB devices and VM disks may expose neither WWN nor serial. The
  deliberate refusal needs a clear message; existing install VM fixtures may
  need a stable serial added to their virtual disks before CI can install.
- A serial or WWN check narrows the device-swap window but cannot make a
  hot-swappable device operation atomic. The checks run immediately before
  each destructive stage. An answers file that names only `/dev/sdX` also
  cannot prove which physical disk its author intended before this process
  began; the installer can establish and preserve only the identity it first
  observes during the run.
- Re-verifying a cached ISO requires the current release checksum to be
  reachable on every use. `#try` already requires the release API; cached
  reuse now also needs the checksum download, by the owner's decision.
- The finish text must follow the *actual* copied/built branch; using only the
  presence of `/etc/nixarchy-reference-*` would misreport fallback builds.

## Verification

- Add a cheap `checks.installer-disk-identity` that runs the built installer
  functions with stubbed `lsblk`, `readlink`, `nix`, and disko. It covers the
  wizard/answers disk, all repository-defined disks, missing WWN and serial,
  a replaced device with the same size and free region, a swap during disko
  build, and no destructive command after refusal. Extend the existing
  `tests/installer-store-space.nix` format fixture to assert an unencrypted
  run never creates the key, an encrypted run exposes it only to disko and
  removes it, and a failed `wipefs` stops before disko.
- Extend `tests/try-preflight.nix` with a stubbed release API, checksum file,
  and download. Assert valid cache reuse after checksum verification, corrupt
  cache deletion and verified replacement, and refusal when checksums or
  replacement bytes are missing. Extend `tests/installer-baked-guard.nix` to
  assert the finish-screen login for actual baked copy versus fallback build,
  free-space, and `--from` paths.
- For **each** new assertion, copy its product file aside outside the worktree
  under `/mnt/data/vmtest/`, remove the relevant guard or return the old
  behavior, run the named check and capture its failing line, restore with
  `cp` (never `git checkout`), then run it green. Break disk rechecks,
  no-identity refusal, LUKS key timing, cache verification, and the copied
  login selection independently. Also swallow `wipefs`'s failing status in
  the product and prove its failure case goes red. Put the red output in the
  PR.
- Build only cheap checks under the shared lock after plan approval. Run
  `nix fmt -- --ci`, statix, deadnix, and scan the diff for added
  `producer | grep -q` and `omarchy/shell.json` writes. CI runs the VM install
  matrix; no local VM or `checks.options` is required for this spec gate.
