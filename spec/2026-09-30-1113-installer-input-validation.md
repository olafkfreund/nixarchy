---
status: draft
issue: 1113
intent: intent/2026-09-30-1113-installer-input-validation.md
---

# Spec: Reject invalid installer inputs before installation

## Design

The cited behavior is present in both `origin/main` and the current `fix/1089-installer-disk-safety` branch. Main's line references below shift by roughly 12–150 lines on #1089; the function names and behavior do not change. Implement after #1089 merges, rebasing this branch onto main and checking the references again.

1. **Names.** Extend the shared `validate_username` and `validate_hostname` in `installer/install.sh:609-635` (#1089: `:621-647`). Preserve their existing ASCII syntax and the `root`/`nixbld*` refusals. Reject usernames longer than 32 bytes and hostnames longer than 63 bytes, with a length-specific message. The accepted alphabet is ASCII, so `${#name}` and byte length agree. Use one explicit reserved-user set for the target's standard accounts: `root`, `bin`, `daemon`, `nobody`, `sshd`, `systemd-network`, `systemd-resolve`, and `nixbld*`; a service-specific name outside that set may still be rejected by NixOS evaluation. Both the wizard (`:720-738`; #1089 `:732-750`) and answers validation (`:1278-1283`; #1089 `:1371-1376`) already call these functions. The `--host` argument also calls `validate_hostname` (`:2892`; #1089 `:3042`).

2. **Timezone and keymap.** In `validate_answers` at `installer/install.sh:1308-1310` (#1089: `:1401-1403`), require the timezone to name a regular zone file under `TZDIR`, not a directory; reject absolute and parent-traversal names. Require a literal keymap basename that matches an actual `.map.gz` file under `KEYMAPS`, without passing user text to `find -name` as a pattern. Preserve the existing specific answers-file error and exit 2; do not replace an invalid answer with a default. The wizard's timezone picker already enumerates files (`:742-747`; #1089 `:754-759`) and its keymap picker uses the curated list (`:600-606`; #1089 `:612-618`).

3. **Wi-Fi SSIDs.** `connect_wifi` uses `nmcli -t -f SSID,SIGNAL,SECURITY` and `awk -F:` at `installer/install.sh:373-402` (#1089: `:385-414`). Parse the terse output on *unescaped* field separators, then decode nmcli's escaped `\:` and `\\` in the SSID before deduplication, display, and `nmcli device wifi connect`. Keep signal sorting and the existing security display. A selected `Cafe:Guest` must reach `nmcli` as `Cafe:Guest`, exactly once, rather than `Cafe` or an escaped spelling.

4. **Hardware-module write.** In `generate_hardware_config` at `installer/install.sh:1710-1739` (#1089: `:1857-1886`), check `write_hardware_modules` and return 1 with a message naming the destination when it fails, before the logging brace group. This preserves the installer phase chain's failure handling (`:3085`; #1089 `:3239`). Keep `write_hardware_modules`' deliberate best-effort hardware detector (`:1759-1785`; #1089 `:1906-1932`) unchanged; a detector failure is distinct from a failed file write.

5. **Regression check.** Add one cheap `tests/installer-input-validation.nix` runCommand and wire it in `flake.nix` beside the other installer checks (`:1941-1999`). Extract and exercise the actual installer functions with minimal stubs. Cover the 32/63 boundaries and a reserved account, a timezone directory and valid zone file, a wildcard keymap that happens to match a file and a literal valid keymap, an escaped-colon SSID through the selected-name and connect path, and a failed `write_hardware_modules` that must stop `generate_hardware_config`. Include ordinary valid inputs so rejection-only implementations fail. Keep output specific enough to identify each case. Avoid a `producer | grep -q` check under pipefail.

## Alternatives rejected

- Separate wizard and answers validators: they can diverge, while the existing shared functions already cover both entry points.
- Checking names against the live ISO's `/etc/passwd`: that image does not define exactly the same users as the installed target; the approved choice is a stable explicit set.
- Accepting timezone directories, treating keymap input as a glob, or silently defaulting invalid answers: each makes an unattended install act on a different value than the user supplied.
- Flattening nmcli output by splitting every colon or dropping signal/security: the first loses valid SSIDs, and the second needlessly changes the current selection UI.
- Making the hardware detector's own failure fatal: its `|| true` is intentional; failure to write the generated file is the issue.

## Risks

- The explicit reserved-name set cannot anticipate every service-specific account in a custom repository; evaluation may still reject such a collision. An overly broad set would also reject usable names.
- nmcli escapes both colons and backslashes in terse output. A parser that handles only `\:` can still corrupt other valid SSIDs; test both escape forms.
- A directory of zoneinfo aliases can contain links; `-f` follows a link to a regular file, while path traversal must still be refused.
- #1089 is editing the same installer script. Rebase after it merges and rerun the new check plus existing installer checks; VM checks remain CI-owned unless separately authorized.

## Verification

- Build `checks.x86_64-linux.installer-input-validation` after implementation. The check must print positive cases and refuse each invalid case for the stated reason.
- Prove every independent assertion can fail: copy `installer/install.sh` aside outside the worktree, remove one fix at a time (name limit/reserved account, timezone file requirement, keymap literal match, SSID escape parsing, hardware-write return check), build the check under the shared lock and capture its failing line, then restore the file with `cp` and show a green run. Never use `git checkout` for restoration. Stage any new check before Nix sees the flake.
- Run the cheap existing checks that cover adjacent behavior, including `installer-answers`, `installer-network`, `installer-store-space`, and `installer-from-repo`. The wizard and full install VM checks run in CI; they must continue to reach their original assertions.
- Before any Nix build, follow the repository's CI-load rule and use the shared build lock. No builds or VM runs occur at this draft-spec gate.
