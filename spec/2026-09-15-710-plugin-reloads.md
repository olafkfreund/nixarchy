---
status: approved
issue: 710
intent: intent/2026-09-15-710-plugin-reloads.md
---

# Spec: an activation that changes no plugin leaves running plugins alone

## Design

Replace the remove-everything-then-relink block in `modules/home.nix` (the
`.nixarchy-managed` block, around line 787) with a reconcile.

- **D1. Relink only what changed.** For each declared plugin, compute
  `id=$(cat drv/id)` and `target=$(readlink -f drv/plugin)`.
  - If `dir/$id` is a real directory, keep today's "your own directory" message
    and skip it.
  - If `readlink "dir/$id"` already equals `target`, do nothing.
  - Otherwise, `run ln -sfn "$target" "dir/$id"`.

  Every declared id is appended to a new manifest list, whichever branch it
  took. An unchanged link therefore gets no unlink and no create, and the
  shell's watcher sees nothing.

- **D2. Remove only what was retired.** For each id in the old manifest that is
  not in the new list, and is a symlink, `run rm -f`. This is today's symlink
  guard, applied to fewer entries.

- **D3. Write the manifest without a spurious event.** Build the new list in
  `.nixarchy-managed.new`, which is hidden and so ignored by the watcher (see
  `localPluginIdForPath`). Then:
  - if the list is empty, remove both files;
  - if it matches the old manifest, remove the `.new` file;
  - otherwise, `mv` it over the old one.

  Dry-run keeps working because every write goes through `run`. There is one
  catch. Under `run`, a dry run writes nothing, so the comparison must read
  what the script would have written, not the file. The plan fixes the exact
  shape of that.

- **D4. The check is `tests/plugin.nix`.** Before `omarchy plugin remove` in
  the declarative half, record the inode of the `remco.bar-toggle` link
  (`stat -c %i`). Then restart `home-manager-omarchy.service` and assert that
  the inode is unchanged: an unchanged plugin was not touched.

  Then, after `plugin remove` has unlinked it, restart the service again and
  assert the link is back, pointing at the same store path: a missing plugin
  is restored.

  Today's code relinks on every activation, so the first assertion goes red
  against current `main` (§1). No new check, so no workflow edit.

## Alternatives rejected

- **Wrap only `ln -sfn` in a target comparison.** The earlier cleanup has
  already deleted the link, as the issue says, so this changes nothing.
- **Raise the shell's 150 ms debounce, or batch reloads in the watcher.** That
  is upstream Omarchy's shell code (§11). It also hides only some cases, since
  the bursts were 4.65 s apart.
- **Asserting on the shell journal ("plugins changed" lines).** It measures the
  watcher, which is upstream's, and a timing-dependent log. The inode is
  exactly the property this code owns: it did not touch the link.
- **A VM step for changed-source and retired-plugin cases.** Each needs a
  second Home Manager generation inside the test, which costs minutes. D2 is
  today's guard with a smaller input set, and D1's changed branch is today's
  `ln -sfn`. Recorded as untested here rather than claimed.

## Risks

- **A stale manifest leaves a link behind.** This happens when an old id
  appears in the old manifest but a failed earlier activation never wrote it.
  Same exposure as today; no worse.
- **`readlink` compares against a non-canonical path.** Both sides use the
  resolved store path (`readlink -f` on the derivation, and the link's own
  target, which D1 always writes resolved). A link written by the old code
  also holds the resolved path, so the first activation after upgrade relinks
  nothing.
- **Mode A.** With no declared plugins and no manifest, the block does nothing.
  With a manifest from an earlier generation, D2 removes those links, as today.
- **Hosts:** every desktop with `programs.nixarchy.plugins`; p620 is the
  reporter.

## Verification

- `checks.plugin`: the inode assertion is red against today's block and green
  with D1–D3. The restore assertion is green.
- `checks.options` passes (§6 local-check rule for `modules/`).
- `checks.session` runs in CI.
- By hand on p620: run `journalctl --user -f -t omarchy-shell` during a rebuild
  that changes no plugin, and see no plugin-change burst from nixarchy's links.
  nixi and voice may still produce one; those are tracked in their own issues,
  per the intent.
