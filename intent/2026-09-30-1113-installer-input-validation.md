---
status: approved
issue: 1113
author: olafkfreund
---

# Intent: Validate installer input before it reaches a disk or generated configuration

## Problem

The findings in #1113 still hold on `origin/main` after #1111 and on the current #1089 branch:

- `installer/install.sh:612-633` accepts arbitrarily long usernames and hostnames. Its username validator rejects `root` and `nixbld*`, but accepts other system account names such as `daemon`.
- `installer/install.sh:1308-1310` accepts a timezone directory because it tests existence, and accepts keymap glob patterns because `find -name` interprets them as patterns.
- `installer/install.sh:377-380` splits `nmcli -t` output on colons. An SSID containing `:` is split at the first colon, so the displayed name and the name passed to `nmcli device wifi connect` are wrong.
- `installer/install.sh:1718-1739` calls `write_hardware_modules` without checking its status. The later logging brace group can succeed after that write fails, allowing the install phase to continue with a missing or partial hardware module file. The detector's internal `|| true` is a separate, deliberate best-effort choice.

The reported `--host` validation issue is already fixed by #1111: `installer/install.sh:1215-1230` handles a host the repository already defines without demanding its answers again, and `:2892` validates the `--host` value. It is outside this issue's scope. The #1089 branch changes disk safety, but leaves the findings above intact.

## Proposed outcome

The wizard and answers-file path reject names that would fail or collide later, accept only actual timezone files and literal keymap names, preserve a colon in a selected Wi-Fi SSID, and stop if writing the generated hardware module file fails. Each refusal names the invalid input or failed file before disk installation continues.

## Affected users and systems

New installs using the ISO wizard or an answers file; Wi-Fi users whose SSID contains a colon; installs that generate hardware modules. Existing installed machines and their configurations are unaffected.

## Constraints

- Use the shared name validators for both wizard and answers-file input.
- Preserve legitimate usernames and SSIDs, including the existing hyphen/digit username forms and SSIDs containing colons.
- Preserve the intentional non-fatal handling of unavailable hardware *detection*; only a failed write of the generated file is fatal.
- #1089 owns nearby installer changes. Implement only after #1089 merges and this branch is rebased onto main; verify the claims again then.
- This is an intent only. No installer edits, builds, VM runs, push, or PR at this gate. Refs #1098 and #1089.

## Open questions

1. **Approved:** cap a hostname label at 63 characters and a username at 32 characters in the shared validators; count bytes in the ASCII-only accepted alphabet.
2. **Approved:** reject names already used by the target's standard system accounts, including `daemon`, in one shared validator. Define a stable explicit set rather than relying on the live ISO's `/etc/passwd`, which may differ from the installed system.
3. **Approved:** refuse an invalid timezone or keymap in an answers file with a specific error; do not silently replace it with a default.
