---
status: approved
issue: 1479
author: olafkfreund
---

# Intent: screencast-restore brings the desktop back exactly

## Problem

`screencast-restore` (`tests/demo/screencast/default.nix`, #930) promises that a recorded
desktop comes back as it was, and that it verifies this rather than trusting the happy path. On
p620 (2026-10-28, nixi#108) it didn't:

- `screencast-prep` had hidden 12 plugins.
- Restore re-enabled them, then reported `shell.json did NOT come back`.
- The bar widgets of the re-enabled plugins (clock, omaspotify, omateams, altscape, omafob,
  bar-folder…) were missing, or had moved to other sections.
- Running restore a second time moved them further.

The snapshot itself was intact, and copying it back by hand restored the desktop (the checksum
matched and stayed stable). So the verify step worked and caught the problem; the restore step
is what broke the layout. It looks as if re-enabling a plugin lets the shell put the plugin's
widgets back where it chooses, overwriting the layout restore just wrote.

## Proposed outcome

- After prep and restore, `~/.config/omarchy/shell.json` matches the snapshot (same checksum),
  every hidden plugin is enabled again, and the bar looks as it did before.
- Running restore again, after a success or a failure, never makes things worse.
- If it still can't get back to the snapshot, it says so and leaves the snapshot in place, as it
  does today.

## Affected users and systems

- Anyone recording with the real-desktop screencast tooling (#930): nixarchy's demo recordings
  and nixi#108.
- Hosts: p620 seen; any host with bar plugins that place widgets.

## Constraints

- Keep #930's rules: refuse rather than mutate, snapshot before touching, verify on the way
  back, never delete the snapshot on failure.
- Never close or change the user's windows or other config.
- It must work while the shell is running, without restarting it mid-session if avoidable.

## Open questions

- Is the overwrite the shell's plugin re-enable rewriting `shell.json`, or a race between
  restore's write and the shell's own save? The spec decides once it's measured.
- Should prep stop hiding plugins this way altogether (e.g. a shell "recording mode" that hides
  without touching `shell.json`)? That is a larger change, and maybe a separate issue.
