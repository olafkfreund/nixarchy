---
status: draft
issue: 1479
intent: intent/2026-10-28-1479-screencast-restore-shell-json.md
---

# Spec: screencast-restore puts each widget back where it was

## Root cause (what the code and the evidence show)

Restore doesn't lose a race with the shell. It asks the shell to put every widget in the wrong
place:

- `screencast-restore` re-enables each hidden plugin with
  `omarchy plugin enable "$id" right` (`tests/demo/screencast/default.nix`, restore loop).
- `right` without an index appends to the end of the right section.
- Prep never records where a widget was, so restore can't say.

The evidence from p620 (2026-10-28) matches exactly. Diffing the kept snapshot
(`~/.local/state/nixarchy/screencast.kept-202610280759/shell.json`) against what restore produced
(`~/.local/state/nixarchy/shell.json.before-manual-restore`):

| Section | Snapshot | After restore |
|---|---|---|
| center | … `promaa.clock` … `io.github.cempack.omaspotify` | both gone |
| centerEnd | `omateams` `nixarchy.meetingai` | `omateams` gone |
| left | … `io.github.qempexe.altscape` `yogeshojha.omafob` … | both gone |
| right | its own order | the same, with all 12 re-enabled widgets appended at the end in restore order |

Widget settings were lost too: `yogeshojha.omafob` came back without `"showRing": true`.
Disabling a plugin removes its widget object, and `enable` creates a fresh one.

A second run moved things further. `setEnabled(id, true, placement)` moves a widget that is
already on the bar, so re-running restore re-appends.

**Proposed — user to confirm at spec review:** this is the cause. No timing change would help.
The shell watches `shell.json` (`shell/shell.qml`, `userConfigFile`, `watchChanges`) and wrote
back exactly what it was told to.

## Design

Keep restore going through the shell's own IPC, as house rule `modules/AGENTS.md:1027` and
`:1603` require (never write `shell.json` under a running shell). Give the IPC enough to put
each widget back exactly.

1. **Prep records placement and settings.**
   - Before disabling anything, for each id in `disabled.json`, prep records every bar widget
     object with that id from the snapshot's `.bar.layout`, as `{section, index, widget}`.
     `widget` is the whole object, settings included (e.g. `showRing`, `format`, the folder's
     `widgets` / `widgetSettings`).
   - This is a pure `jq` read of the snapshot, written into `manifest.json` next to `disabled`.
   - Bar-kind plugins (`kinds` contains `bar`) have no widget and keep today's path.
2. **Restore places them, in order.**
   - For each section, sort the recorded widgets by `index` ascending.
   - Put each one back with `omarchy-shell shell putBarWidget <id> '{"section":S,"index":I}'`.
     Ascending order makes every recorded index valid when it is used: all widgets before it are
     either still there (never hidden) or were just put back.
   - `putBarWidget` is the shell's idempotent writer ("enable, but only where the widget is not
     on the bar already", `PluginRegistry.qml:339`), so a re-run leaves an already-placed widget
     alone instead of moving it.
3. **Restore puts settings back.**
   - For each recorded widget, set every key except `id` with
     `omarchy-shell shell setBarWidget <id> <key> <json-value> '{"section":S}'`, the shell's own
     setting writer.
   - Setting a key to the value it already has is a no-op, so a re-run is harmless.
4. **Verify as today, unchanged.**
   - Settle, then compare the checksum, then compare the `jq -S` normalised form.
   - On success, remove the state dir. On failure, print the diff and keep the snapshot.
   - The current failure message says "shell.json did NOT come back"; it gains one line naming
     `screencast-recover`.
5. **An old manifest (no placement recorded) still restores the old way**, with a warning that
   positions may differ. A take from before this change can still be recovered.

Not changed: the theme and idle restore, prep's refusals, the snapshot and checksum, and which
plugins prep hides.

**Proposed — user to confirm at spec review:** keep prep's hide-by-disabling approach and fix
restore. A shell "recording mode" that hides widgets without touching `shell.json` would be
cleaner, but it's a shell feature (a carried patch to `shell.qml` plus a renderer flag). It is
a separate issue if wanted. Nothing in the code makes it trivial today.

## Alternatives rejected

- **Copy the snapshot over `shell.json` at the end of restore.** This worked by hand on p620,
  where the checksum held. But it breaks the documented rule that a second writer loses updates
  in both directions, and the shell may write in the gap. It's also what #930 deliberately
  didn't do. Kept only as the manual recovery that the failure message already implies.
- **Stop the shell, write the file, start the shell.** This is correct by the house rule, but it
  restarts the user's bar at the end of every take (a visible flash, and plugins re-initialise),
  for something the IPC can do.
- **`omarchy plugin enable <id> --section S --index I`.** It places correctly, but it moves a
  widget that's already on the bar, so it isn't idempotent. A re-run after a partial failure
  would shuffle again. `putBarWidget` exists for exactly this.
- **Retry or settle longer.** It doesn't address the cause: the placement was wrong, not late.

## Risks

- **A widget id appearing more than once** (two instances in different sections). Record every
  instance. `putBarWidget` skips an id already on the bar, so a second instance would not come
  back. Prep checks for this and refuses with the ids, rather than recording something it can't
  restore. None on p620 today.
- **Nested folder contents.** Hidden plugins that sat inside another hidden plugin's folder
  (`bar-folder`'s `widgets`) come back through the folder's own `widgets` setting, not as
  top-level widgets. On p620 the folder is itself hidden, so its `widgets` value is restored by
  step 3.
- **The registry still scanning.** `putBarWidget` returns "not ready" while the manifest scan
  runs. Restore retries that one answer for a bounded time (a few seconds), then reports failure
  and keeps the snapshot.
- **Hosts:** any host recording with #930's tooling. p620 and razer have used it.

## Verification

- **Unit (jq, in `nix flake check` with the other screencast checks).**
  - The placement extraction is run against a fixture copy of the p620 snapshot (redacted to
    widget ids and settings). It yields the 12 recorded widgets with the sections and indices
    in the table above, and `showRing` for omafob.
  - A manifest without placement takes the legacy path.
- **Idempotence (unit).** Applying the restore plan to a model of the post-prep layout gives the
  snapshot layout. Applying it twice gives the same.
- **Live on p620 (lead, with the user's consent, desktop prepared as for a take).**
  - `screencast-prep` then `screencast-restore` reports "byte-identical" or "equivalent", and the
    bar looks as before.
  - Running `screencast-restore` again says "nothing to restore".
  - Killing restore halfway, then `screencast-recover`, also ends equivalent.
