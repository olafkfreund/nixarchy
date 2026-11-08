---
status: approved
issue: 1646
spec: spec/2026-11-08-1646-stock-iso-check.md
coders:
  2: codex  # the ISO pin and the kernel/initrd extraction derivation
  3: codex  # the server node: nginx vhosts, an empty cache.nixos.org, mkBinaryCache roots
  4: codex  # the stock machine and its serial script, after tests/install.nix's create_machine pattern
  5: codex  # list memberships and the weekly job, a CI change the owner merges
  6: codex  # the manual section
reviewers:
  - codex  # a VM harness whose break must be explained by one cause only
  - agy    # an independent read of the same diff
---

# Plan: a check proves the stock NixOS ISO install path (#1646 Part B)

## Decisions carried from the approved spec

1. **The gap is booting the actual stock ISO and completing an install from
   it.** The dark-cache refusal stays with `checks.installer-refusal`
   (`tests/installer-refusal.nix:2-30`). A stock ISO has `cache.nixos.org`,
   so `preflight_build` (`installer/install.sh:2578`) runs there: it probes
   over HTTP (`:2582-2584`), then dry-runs with `SUBSTITUTE_FLAGS` (`:73`).
2. **Two machines, `tests/install-stock-iso.nix`:**
   - **`server`**: nginx with one self-signed cert for `cache.nixos.org`,
     `nixarchy.cachix.org` and `hyprland.cachix.org`, after
     `installer-refusal`'s pattern (`:37-44`). `cache.nixos.org` is an
     **empty cache** (`nix-cache-info` returns 200, every `.narinfo` 404s).
     The two cachix names serve one `pkgs.mkBinaryCache`, whose roots are the
     reference install's closure, the `install` package, and every
     `inputs.self.lib.inputSources` path. There is also a 9p share with the
     CA bundle, an answers file and the `install` store path.
   - **`stock`**: `create_machine` with a start command, after
     `tests/install.nix:594`'s pattern. It boots the pinned ISO **under
     UEFI**, OVMF as pflash (`tests/install.nix:143-144`), as `-cdrom`, with
     the ISO's kernel and initrd extracted and booted with its own
     parameters plus `console=ttyS0`. It gets a blank 32 GiB virtio target
     and the 9p share.
3. **Serial script:** `test -d /sys/firmware/efi` (a named failure
   otherwise); mount the share; the three hostnames go in `/etc/hosts`;
   `SSL_CERT_FILE` and `NIX_SSL_CERT_FILE` point at the bundle;
   `nix copy --from https://nixarchy.cachix.org --no-check-sigs <install>`;
   then `<install>/bin/nixarchy-install --answers /mnt/share/answers`. It
   asserts exit 0, and that the target's `/etc/nixarchy/` names the answers'
   host. It prints the time to the first log line, the bytes served (from
   nginx's log) and the peak overlay use.
4. **Offline inputs:** the generated flake pins nixarchy by commit
   (`installer/mkFlake.nix:25`) and locks the rest by `narHash`. With every
   `inputSources` path in the served cache, Nix substitutes them by store
   path through `SUBSTITUTE_FLAGS`.
5. **§1 break:** drop `extra-substituters` and `extra-trusted-public-keys`
   from `SUBSTITUTE_FLAGS` (`:73`). The HTTP probes still pass. The dry-run
   knows only the empty `cache.nixos.org`, so planning fails with "the
   system cannot be planned, so no install was started". Only the flags
   explain that.
6. **Pin:** `data/stock-iso.nix`, `{ url; hash; }`, for the exact 26.05
   minimal ISO path on `releases.nixos.org`. It is refreshed by hand.
7. **Weekly (owner), not nightly.** `install-stock-iso` joins `claimed`
   (`.github/scripts/generated-checks.sh:43`), so it is off pull requests
   (`:127`), and `nightly_only` (`:77`), the keep-alive skip list. A
   `weekly.yml` job sits beside `stable-session` (`:90`) on
   `[self-hosted, nixos, kvm, big]`. **A CI change: the owner merges it.**
8. **Manual:** `docs/manual/the-iso.md` gains "From a stock NixOS ISO".
9. **Limit:** the manual's `nix run github:` fetch of the installer is not
   exercised.

## Steps

1. **Probes that must pass before anything else** (session, read and
   evaluate only). Stop and report to the owner if either fails.
   - **`inputSources` coverage.** Build the generated flake's lock the
     installer would write. `installer-lock`'s check already does: read its
     output, or evaluate `installer/mkFlake.nix` for the reference host.
     Then compare every locked input's `narHash` store path with
     `nix eval --json .#lib.inputSources ...` (as `tests/iso-source.nix:4`
     calls it). Every locked input must be in the list.
   - **The ISO's boot layout.** Fetch the pinned ISO once to the
     scratchpad (`nix store prefetch-file`, giving the hash for step 2), and
     list its boot files (`bsdtar -tf`): confirm the kernel, the initrd and
     the kernel-parameter source (`/EFI/boot/grub.cfg` or
     `/isolinux/isolinux.cfg`), and record the parameters the default entry
     uses.

   Traps: data only, never run anything from the ISO. A coverage gap means
   decision 4 is false, and the spec goes back to the owner.

2. **Pin and extraction** (Codex): `data/stock-iso.nix` with step 1's URL
   and hash. A small derivation fetches it (`fetchurl`) and extracts the
   kernel and initrd (`bsdtar -xf ... <paths>`) into `$out`, plus a
   `cmdline` file holding the default entry's parameters (fixed text taken
   from step 1, asserted by `grep` against the ISO's config, so a changed
   layout fails loudly).
   Verify: `nix build` of the derivation (package tier) yields three files.

3. **Server node** (Codex), decision 2's `server`, in `tests/install-stock-iso.nix`.
   Verify: `nix eval` of the test's `driverInteractive` drvPath; the
   `mkBinaryCache` roots include the `inputSources` list.
   Traps: `mkBinaryCache` of a full closure is several GB. It is built only
   by the weekly job and the local VM run, never on a pull request.

4. **Stock machine and serial script** (Codex), decisions 2 and 3, after
   `tests/install.nix:594`'s `create_machine` call and `:143-144`'s pflash
   lines. Use the driver's console helpers (`wait_for_console_text`,
   `send_console`).
   Verify: VM tier, one slot, gate free: `nix eval --raw ...drvPath`, then
   `nix build '<drv>^*' -L`. The install completes and the three numbers
   print. §1 (decision 5): commit a known-good baseline, then build with the
   two options removed from `install.sh:73`. It must fail on "the system
   cannot be planned". Capture that and restore from `HEAD` (§5).
   Traps: `mkFlake` needs a committed tree (§5), so commit before
   building. Never `pkill` by name (§6). A guest-side timeout beside an
   install is load, not a bug (§6), so run only with no runner busy.

5. **Lists and the weekly job** (Codex): add `install-stock-iso` to
   `claimed` (`generated-checks.sh:43`) and to `nightly_only` (`:77`). Add a
   `weekly.yml` job on its own cron entry (Sunday, after `stable-session`'s
   09:00), with `timeout-minutes` set from step 4's measured wall time ×
   1.5, building `.#checks.x86_64-linux.install-stock-iso`.
   Verify: `bash .github/scripts/generated-checks.sh generated` does not
   list it. The coverage guard step in `build.yml` passes locally (it is a
   shell step: run its script). `actionlint` on `weekly.yml`.
   Traps: `case` membership wants spaces on both sides, and the lists are
   collapsed first (`:86-88`). A new name at a line end is fine after that.

6. **Manual** (Codex): `docs/manual/the-iso.md`, "From a stock NixOS ISO":
   boot in UEFI mode, connect, `nix run github:olafkfreund/nixarchy#install`,
   what the preflight does when our caches are unreachable, and the RAM
   note. Verify: `checks.doc-options` and `docs-lists`.

7. **Run, commit, PR** (session): cheap tier (`install-gate`,
   `grep-q-pipefail`, `doc-options`, `docs-lists`, fmt, statix, deadnix),
   the VM run from step 4. The PR body says the weekly job is a CI change
   for the owner to merge.

## Tests (by §6 tier)

| tier | check | expect |
|---|---|---|
| cheap | `install-gate`, `grep-q-pipefail`, `doc-options`, `docs-lists`, fmt, statix, deadnix; `generated-checks.sh generated` omits it | pass |
| package | the extraction derivation | kernel, initrd, cmdline |
| VM | `install-stock-iso` | installs; fails on "cannot be planned" with the flags dropped |

Not run on pull requests, by design: `install-stock-iso` (weekly).

## Rollback

Revert the merge commit. Nothing ships to users. The check, the pin, the
weekly job and the manual section go together.

## PR notes

`Closes #1646` (Part A merged in #1669; this is the remainder). The body
links the intent, the spec and this plan, says which steps Codex did,
carries step 1's probe results and the §1 output, and flags `weekly.yml` as
the owner's merge (§11). Comment "@codex review". Merge with a merge commit
(`--merge`).

## Deviations (Codex plan review, 2026-11-08)

1. **RAM:** the stock machine gets 8 GiB. The ISO's overlay is half of
   memory (install.sh's live-store check), and the install needs room for
   the closure in the overlay; the check prints the peak overlay use.
2. **Registration:** `checks.install-stock-iso` is added to `flake.nix`'s
   checks beside the other installer checks (step 4).
3. **Verifications that can fail:** step 3 boots the server alone and
   `curl`s `nix-cache-info` and one closure `.narinfo` from the client
   side. Step 6's list entries are checked with
   `generated-checks.sh generated | grep -c install-stock-iso` = 0.
4. **OVMF vars are a writable copy** (`cp` to the test's tmp, then
   `-drive if=pflash,...` writable), per the spec. `tests/install.nix:143`
   uses a read-only drive, which is not the pattern here.
5. **Step 1's coverage probe:** call `lib.inputSources { flake = self; }`
   as `tests/iso-source.nix:4` does, through `nix eval --impure --expr`
   on the flake, not `.#lib.inputSources` with no argument.

## Step 1 result (session, 2026-11-08)

Both probes pass.
- **Coverage:** every top-level input of the flake is in
  `lib.inputSources { flake = self; }` (0 missing). Only top-level inputs
  were compared, not `follows` targets.
- **ISO pin:** `https://releases.nixos.org/nixos/26.05/nixos-26.05.13627.c56a87d8e41c/nixos-minimal-26.05.13627.c56a87d8e41c-x86_64-linux.iso`,
  `hash = "sha256-EqYJQWEILG4gNInsYaQhU0yJGSLJIBdpx+6AuLwoNQE="`.
- **Boot layout:** UEFI via `EFI/BOOT/BOOTX64.EFI` and `EFI/BOOT/grub.cfg`
  (also `isolinux/isolinux.cfg`). It carries two kernels, 6.18.60 and
  7.3.1, each with its own `initrd` under `boot/nix/store/...`. The default
  grub entry boots
  `linux /boot//nix/store/jyb28mnq...-linux-6.18.60/bzImage ${isoboot} init=/nix/store/380213xj...-nixos-system-.../init nohibernate root=fstab loglevel=4 lsm=landlock,yama,bpf`.
  Booting the ISO through OVMF and grub (not a direct kernel boot) avoids
  depending on these paths; the extraction derivation is needed only if
  the test boots the kernel directly.
