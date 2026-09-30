---
status: approved
issue: 1090
author: olafkfreund
---

# Intent: Protect user editor and agent settings from Home Manager writers

## Problem

The issue's JSONC failure is real but its "silently" claim is overstated. `modules/home.nix` merges Zed, VS Code, and Cursor `settings.json` with `jq`; comments or trailing commas make that merge fail, leaving nixd unconfigured. The helper already prints `nixarchy: could not merge nixd into ...` to stderr, though the message does not explain JSONC or how to finish the setup.

The managed-symlink claims hold. `mergeJson` moves a temporary file over an existing symlink, replacing Home Manager's link. `appendToml` appends through a symlink to its target, which can fail on a read-only store file or write outside the intended file. `omarchy-theme-set-zed` redirects into `settings.json` through a symlink on a successful merge. Its separate JSONC failure path already leaves the file alone and reports why.

## Proposed outcome

Activation and theme changes leave Home Manager-managed links and their targets untouched and give a useful message when they skip a file. Users with JSONC editor settings receive an actionable message if nixd cannot be merged; their comments and other settings remain intact. Ordinary writable files continue to receive the intended settings.

## Affected users and systems

Home Manager users enabling nixd in Zed, VS Code, Cursor, or Helix; users enabling the NixOS or ai-mirror MCP entries in Claude Code, opencode, or Codex; and Zed users changing Omarchy themes. The `mergeJson` and `appendToml` helpers serve multiple callers, so the fix must cover all of them, not only the editors named in the issue.

## Constraints

- Preserve user-authored settings and comments; never unlink or overwrite a managed symlink to make an activation succeed.
- Keep the existing opt-in gates and Mode A behavior. A Home Manager module is applied through a NixOS rebuild, not `home-manager switch`.
- Add a check that demonstrably fails against the old behavior and passes with the fix. Do not mask a failed merge or append as success without a visible explanation.
- Do not edit `tests/options.nix` while the unpushed criticals PR owns it. If option coverage is needed there, sequence that edit after its merge. Do not edit the other protected installer or microVM paths.
- No Nix builds or PR in this intent round.

## Open questions

1. **Decided:** skip JSONC with specific guidance. A safe rewrite must preserve comments and formatting; do not add a parser or perform a lossy rewrite.
2. **Decided:** skip Home Manager-managed symlinks with guidance to declare the setting in Home Manager or make the file user-owned. Do not materialize a writable copy.
3. **Decided:** a failed JSONC merge stays nonfatal to activation; print the reason and manual remedy so unrelated configuration can activate.
