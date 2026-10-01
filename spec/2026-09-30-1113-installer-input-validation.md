---
status: approved
issue: 1113
intent: intent/2026-09-30-1113-installer-input-validation.md
---

# Spec: Reject invalid installer inputs before installation

**Owner-approved revision:** the build-time name list uses each evaluated user's
`.name`, reaches the installer through a top-level `RESERVED_USERS` variable,
and is tested through the rendered installer package. The timezone and Wi-Fi
decisions below are also owner-approved revisions to the first approved spec.

## Design

The cited behavior is present in both `origin/main` and the current `fix/1089-installer-disk-safety` branch. Main's line references below shift by roughly 12–150 lines on #1089; the function names and behavior do not change. Implement after #1089 merges, rebasing this branch onto main and checking the references again.

1. **Names.** Extend the shared `validate_username` and `validate_hostname` in `installer/install.sh:609-635` (#1089: `:621-647`). Preserve their existing ASCII syntax and the `root`/`nixbld*` refusals. Reject usernames longer than 32 bytes and hostnames longer than 63 bytes, with a length-specific message. The accepted alphabet is ASCII, so `${#name}` and byte length agree. Generate the reserved target-name list **at build time** from `self.nixosConfigurations.reference.config.users.users`: take each non-normal user's `.name` value (not the attribute key), and add `daemon`, which that evaluated list misses. This keeps the reference's normal `omarchy` user valid. Splice the list into a top-level `RESERVED_USERS=@reservedusers@` assignment in `installer/install.sh:37-38`, beside `TZDIR` and `KEYMAPS`; `validate_username` reads that variable, so raw-function fixtures can set it explicitly. Add the substitution in `flake.nix:954-1021`, beside `@initrdmodules@`. Do not query the live ISO's `/etc/passwd` at install time. A service-specific account outside the reference set may still collide on a custom target. Both the wizard (`:720-738`; #1089 `:732-750`) and answers validation (`:1278-1283`; #1089 `:1371-1376`) already call these functions. The `--host` argument also calls `validate_hostname` (`:2892`; #1089 `:3042`).

2. **Timezone and keymap.** Add small `validate_timezone` and `validate_keymap` functions called by `validate_answers` at `installer/install.sh:1308-1310` (#1089: `:1401-1403`). A timezone must be a relative path without parent traversal to a regular file under `TZDIR` whose first four bytes are `TZif`; existence or `-f` alone wrongly accepts `zone.tab`. A keymap must be a literal basename matching an actual `.map.gz` file under `KEYMAPS`, without passing user text to `find -name` as a pattern or using a `producer | grep -q` pipeline. Preserve the specific answers-file error and exit 2; do not replace an invalid answer with a default. The wizard's timezone picker already enumerates files (`:742-747`; #1089 `:754-759`) and its keymap picker uses the curated list (`:600-606`; #1089 `:612-618`).

3. **Wi-Fi SSIDs.** `connect_wifi` uses `nmcli -t -f SSID,SIGNAL,SECURITY` and `awk -F:` at `installer/install.sh:373-402` (#1089: `:385-414`). Put its list parsing in a small function. Request `nmcli -t -e no -f SIGNAL,SECURITY,SSID`: the first two fields are bounded, so split only at their first two colons and treat the remainder as the literal SSID. Keep deduplication, signal sorting and security display. A selected `Cafe:Guest` or an SSID containing a backslash must reach `nmcli device wifi connect` byte-for-byte, exactly once, without escape decoding.

4. **Hardware-module write.** In `generate_hardware_config` at `installer/install.sh:1710-1739` (#1089: `:1857-1886`), check `write_hardware_modules` and return 1 with a message naming the destination when it fails, before the logging brace group. This preserves the installer phase chain's failure handling (`:3085`; #1089 `:3239`). Keep `write_hardware_modules`' deliberate best-effort hardware detector (`:1759-1785`; #1089 `:1906-1932`) unchanged; a detector failure is distinct from a failed file write.

5. **Regression check.** Add one cheap `tests/installer-input-validation.nix` runCommand and wire it in `flake.nix` beside the other installer checks (`:1941-1999`). Its rendered source is `${self.packages.${system}.install}/bin/nixarchy-install`, **not** the raw `./installer/install.sh` passed as `installScript` to older checks. Extract `RESERVED_USERS` and the actual functions from that rendered file. Call `validate_username` for a named evaluated system user such as `messagebus`, and for `daemon`, while permitting normal `omarchy`; do not merely compare two copies of the same Nix expression. Cover the 32/63 boundaries, a timezone directory and `zone.tab` versus a valid TZif file, a wildcard keymap that happens to match a file versus a literal valid keymap, colon and backslash SSIDs through the selected-name/connect path, and a failed `write_hardware_modules` that must stop `generate_hardware_config`. The nmcli fixture must honor the requested `-e` and `-f` arguments so reverting the field-order/escape fix makes the SSID case fail for that reason. Include ordinary valid inputs so rejection-only implementations fail. Keep output specific enough to identify each case. Avoid a `producer | grep -q` check under pipefail.

## Alternatives rejected

- Separate wizard and answers validators: they can diverge, while the existing shared functions already cover both entry points.
- Checking names against the live ISO's `/etc/passwd` or maintaining a handwritten account list: either can diverge from the evaluated reference system. Add only the known missing `daemon` name explicitly.
- Accepting timezone directories, treating keymap input as a glob, or silently defaulting invalid answers: each makes an unattended install act on a different value than the user supplied.
- Parsing nmcli escapes in an SSID-leading field or dropping signal/security: placing bounded fields first with `-e no` is simpler, and the existing selection UI retains its information.
- Making the hardware detector's own failure fatal: its `|| true` is intentional; failure to write the generated file is the issue.

## Risks

- The reference user set cannot anticipate every service-specific account in a custom repository; evaluation may still reject such a collision. Filtering on `isNormalUser` is necessary so the reference's `omarchy` account remains available.
- An SSID may contain colons and backslashes. With `-e no`, the parser must preserve the remainder of each row byte-for-byte; a newline in an SSID remains outside this line-oriented UI's scope.
- A directory of zoneinfo aliases can contain links; `-f` follows a link to a regular file, while path traversal must still be refused. Some regular files in `TZDIR`, such as `zone.tab`, are not TZif data.
- #1089 is editing the same installer script. Rebase after it merges and rerun the new check plus existing installer checks; VM checks remain CI-owned unless separately authorized.

## Verification

- Build `checks.x86_64-linux.installer-input-validation` after implementation. The check must print positive cases and refuse each invalid case for the stated reason.
- Prove every independent assertion can fail: copy `installer/install.sh` aside outside the worktree, remove one fix at a time (name limit/reserved account, timezone/TZif requirement, keymap literal match, SSID field parsing, hardware-write return check), build the check under the shared lock and capture its failing line, then restore the file with `cp` and show a green run. Also copy `flake.nix` aside and remove the reserved-name splice to prove the evaluated-list assertion goes red, then restore with `cp`. Never use `git checkout` for restoration. Stage any new check before Nix sees the flake.
- Run the cheap existing checks that cover adjacent behavior, including `installer-answers`, `installer-network`, `installer-store-space`, and `installer-from-repo`. The wizard and full install VM checks run in CI; they must continue to reach their original assertions.
- Before any Nix build, follow the repository's CI-load rule and use the shared build lock. No builds or VM runs occur at this draft-spec gate.
