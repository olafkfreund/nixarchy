---
status: approved
issue: 1090
intent: intent/2026-09-30-1090-home-manager-writers.md
---

# Spec: Protect Home Manager settings writers

## Design

1. In `modules/home.nix:207-225`, make `mergeJson` check `-L "$conf"` before the `-s` initialization or `jq` merge. A link is left intact, with a message explaining that Home Manager owns the file and that the user should declare the setting there or make the file user-owned. This applies to all callers: Claude Code and opencode MCP entries (`modules/home.nix:1372-1426`) and the Zed, VS Code, and Cursor nixd entries (`modules/home.nix:1454-1487`). For a regular JSONC file, keep the current nonfatal skip, but change the generic error at `modules/home.nix:223` to identify non-plain JSON and give the path and manual setting guidance. Do not strip comments or rewrite the file.
2. In `modules/home.nix:236-258`, give `appendToml` the same symlink guard before its `-e` initialization or `>>` append. This covers Codex MCP and Helix nixd (`modules/home.nix:1390-1513`). The existing table-presence guard remains; a regular user-owned TOML file still receives the table once.
3. In `pkgs/omarchy/nix-bin/omarchy-theme-set-zed:202-212`, skip a symlinked `settings.json` before either output redirection and print the same ownership guidance. Generating the separate theme palette remains allowed. Preserve the existing JSONC behavior at lines 198-207: no edit, with the theme-specific manual instruction.
4. Add a cheap `tests/home-manager-writers.nix` check, wired through `flake.nix` near `checks.theme-set-zed` (`flake.nix:2132-2136`). Evaluate `modules/home.nix` through a small `home-manager.lib.homeManagerConfiguration` fixture with nixd and Zed/Helix enabled, then run those evaluated activation entries against regular, JSONC, and symlinked settings under a sandbox home. Assert regular JSON/TOML changes, JSONC remains byte-identical with specific guidance, symlink inode and target remain unchanged, and activation returns successfully for both skips. This uses the module's produced scripts rather than a hand-copied implementation.
5. Extend `tests/theme-set-zed.nix:86-113` with a symlinked `settings.json` fixture. Run the packaged setter and assert the link and target are unchanged, the skip message is visible, and the generated theme palette still exists. Existing normal JSON and JSONC cases continue to pass.

## Alternatives rejected

- Parse JSONC and rewrite it as JSON: this discards comments and formatting from user settings. A comment-preserving editor is outside this repair.
- Unlink a Home Manager-managed file or copy its store target into a writable file: this fights the next activation and silently changes ownership of the setting.
- Fail the whole activation when a settings file is JSONC or managed: unrelated Home Manager changes should still activate; the skip must instead explain the manual action.
- Only guard the three nixd editor call sites: the shared helpers also write MCP and Helix files, so a caller-specific guard leaves the same bug elsewhere.

## Risks

- Users whose settings are Home Manager-managed will have to declare the nixd/MCP/theme setting in Home Manager or make the file user-owned; the writer cannot safely add it for them.
- Zed, VS Code, and Cursor users with JSONC settings still need a manual nixd edit. The clearer message must not claim the writer succeeded.
- An existing symlink to a writable, user-owned target is also skipped. This favors preserving the link and its ownership over guessing whether it is safe to write through.
- `tests/options.nix` is owned by the unpushed criticals PR. Do not edit it or run `checks.options` locally; the new cheap check covers these runtime paths without a conflict.

## Verification

- `nix build .#checks.x86_64-linux.home-manager-writers --print-build-logs` exercises the evaluated activation scripts and reports the JSONC and symlink cases. Prove the check can fail: copy `modules/home.nix` aside, temporarily remove each helper's symlink guard in turn, build and capture the failure, then restore with `cp` (never `git checkout`) and build green. Also break the JSONC guidance once and confirm its assertion fails.
- `nix build .#checks.x86_64-linux.theme-set-zed --print-build-logs` covers the packaged setter. Copy `pkgs/omarchy/nix-bin/omarchy-theme-set-zed` aside, remove its guard, capture the failed symlink assertion, restore with `cp`, and show green.
- After any `.nix` edit: `nix fmt`, inspect `git diff --stat`, then `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .`. Keep new files git-tracked before building so the flake sees them. Put red output in the eventual PR.
