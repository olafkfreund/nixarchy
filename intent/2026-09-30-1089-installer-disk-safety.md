---
status: draft
issue: 1089
author: olafkfreund
---

# Intent: Make installer disk identity and image use trustworthy

## Problem

The installer remembers a selected disk by its `/dev` name, which can be
reused by another disk before formatting. The free-space region is measured
again, but the disk's serial or WWN is not (`installer/install.sh:774-808`,
`:1519-1538`). A repository-defined disk is listed with its serial before
preflight, but is likewise not checked again when disko runs (`:1440-1471`,
`:1630-1669`).

`installer/try.sh:243-249` reuses a cached release ISO without checking the
checksum again. A file changed after its first download can therefore be
booted as though it were verified. An offline install intentionally copies the
reference system, whose first-boot login is `omarchy` until an online rebuild
(`installer/install.sh:2607-2630`); the finish screen instead names the
username the installer asked for (`installer/lib/dashboard.sh:201-210`).

One related #1098 finding touches the same formatting function: it writes
`/tmp/nixarchy-luks.key` even when encryption is off, and before building the
disko script (`installer/install.sh:1643-1669`). The password can therefore
sit in a temporary plaintext file while that build runs without needing it.

The #1089 `wipefs` finding is already closed by #1111: `wipefs` is the last
command in `partition_free_space` (`installer/install.sh:1609`), so its failure
is the function's status, and `format_disk` checks it with `|| return 1`
(`:1640`). This work should retain and prove that behavior, not duplicate it.

## Proposed outcome

- Every disk the installer is about to alter is still the physical disk the
  user selected or accepted, with an actionable refusal if its stable identity
  changed or cannot be established.
- A cached release image is verified before use, and a corrupted cached copy
  cannot boot.
- The offline finish screen names the account that can actually log in before
  the first online rebuild.
- The LUKS passphrase file exists only for an encrypted disko execution and is
  removed on success or failure; a failed wipe remains a failed install.

## Affected users and systems

Interactive and answers-file installs, including free-space and `--from`
installs; users of `nix run ...#try`; users installing from the offline ISO.
The installer may refuse hardware whose disks do not expose a stable identity.

## Constraints

- No formatting may begin when disk identity is missing or changed. Never
  infer consent from a reused `/dev` name or a same-sized free region.
- Preserve the #1111 phase chain, repository-disk confirmation, baked-system
  guard, and answers parsing. Keep passwords and LUKS passphrases out of the
  generated flake and logs.
- Prove each new check goes red when its corresponding safeguard is removed,
  then green when restored. Use cheap checks where possible; no local VM or
  Nix build at this intent gate.
- Do not conflate this with the other #1098 installer-validation findings:
  hostname and username lengths, system account names, timezone directories,
  keymap glob characters, Wi-Fi SSIDs containing `:`, and swallowed
  `write_hardware_modules` errors all still hold in separate functions
  (`installer/install.sh:377-380`, `:612-634`, `:1308-1312`, `:1710-1739`).
  The #1098 `--host` syntax-validation finding is already fixed: `main`
  validates it before clone, even for an existing repository host (`:2889-2896`).

## Open questions

1. Should the remaining #1098 validation findings be a separate installer
   follow-up? **Recommend yes:** they concern network and answer parsing or
   hardware generation, rather than the disk-identity and format boundary.
   Keep the LUKS-file finding here because it is in `format_disk`.
2. What if a chosen disk exposes neither serial nor WWN? **Recommend fail
   closed** before writing, with a message to choose a disk whose identity can
   be checked. A size or `/dev` path cannot prove it is the same device.
3. When re-verifying a corrupt cached ISO, should `#try` delete it and
   download it again automatically? **Recommend delete and redownload**, then
   verify the replacement; refuse if the checksum or download is unavailable.
