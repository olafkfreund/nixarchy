---
status: approved
issue: 710
author: olafkfreund
---

# Intent: an activation that changes no plugin leaves running plugins alone

## Problem

Every Home Manager activation deletes and recreates every declared Omarchy
plugin link, even when nothing about the plugins changed. The block in
`modules/home.nix` (around line 787):

1. reads `.nixarchy-managed`;
2. removes every symlink listed in it;
3. deletes that file;
4. re-links every declared plugin with `ln -sfn`.

The shell's `PluginRegistry.qml` watches that directory. Each delete and
create triggers a reload of all plugins, not just the one that changed.

On p620 one `nixos-rebuild` caused bursts 4.65 s apart, which is too far apart
for the shell's 150 ms debounce to merge. It also caused about 38 s of reload
activity and "destroyed during incubation" errors.

## Proposed outcome

- **Unchanged plugins:** an activation that does not change plugin sources
  creates no filesystem events in `~/.config/omarchy/plugins`, so the shell
  does not reload.
- **Real changes:** a changed plugin is re-linked, a removed plugin's link goes
  away, a new plugin appears, and a user's own real directory is still left
  untouched.
- **Bookkeeping:** `.nixarchy-managed` stays accurate, including when no
  plugins are declared, where the file is absent.
- **Regression check:** `checks.plugin` proves a repeat activation leaves the
  plugin links untouched, and that add, change and remove still work.

## Affected users and systems

- Every desktop with `programs.nixarchy.plugins` declared, on each rebuild.
- `modules/home.nix` (the activation block) and `tests/plugin.nix`.

## Constraints

- **Scope:** this covers nixarchy's activation writer only. The watcher's
  whole-registry reload, its filter of temporary names, and Omaplug's eager
  panel are shell or plugin code owned upstream. They are not patched here
  (AGENTS.md §11), only noted for routing, and nothing is filed upstream
  without asking.
- **No new machinery:** no daemon, cache or change to the debounce timer.
- **Seen red first:** the check must fail against today's activation (§1).
- **Mode A:** nothing changes for a host that declares no plugins.

## Open questions

Resolved at approval (the owner accepted the recommendations):

1. **Other writers:** the nixi and voice plugin writers get a separate issue
   each, owned by their input modules. #710 covers nixarchy's activation only.
