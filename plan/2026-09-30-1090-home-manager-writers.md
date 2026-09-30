---
status: draft
issue: 1090
spec: spec/2026-09-30-1090-home-manager-writers.md
---

# Plan: Protect Home Manager settings writers

`mergeJson` and `appendToml` in `modules/home.nix` write runtime settings for multiple agents and editors; the Zed theme setter is a third writer. All three must leave symlinked settings and their targets untouched, with a useful explanation. Plain writable JSON and TOML still receive their settings. JSONC and malformed JSON remain untouched and the skip is nonfatal, with specific guidance for a manual edit. Do not add a JSONC parser, materialize symlinks, or make unrelated Home Manager activation fail. This covers Mode A and the existing opt-in gates. Home Manager remains applied through a NixOS rebuild, not `home-manager switch`.

## Steps

1. `modules/home.nix:207-225`: add `-L "$conf"` handling before `-s`, `jq`, or `mv` in `mergeJson`; print the path and explain how to declare the setting in Home Manager or make the file user-owned. Improve the parse-error message so a JSONC or malformed file is identified as non-plain JSON and the user is told to edit it manually. Keep the skip nonfatal and the existing recursive merge for ordinary JSON. This covers Claude Code/opencode MCP at `modules/home.nix:1372-1426` and Zed/VS Code/Cursor nixd at `modules/home.nix:1454-1487` -> verify by `checks.home-manager-writers` symlink, JSONC, and regular-JSON cases.
2. `modules/home.nix:236-258`: add the same `-L "$conf"` skip before `-e`, `grep`, or `>>` in `appendToml`; keep its existing table-presence guard and ordinary TOML append. This covers Codex MCP and Helix nixd at `modules/home.nix:1390-1513` -> verify by `checks.home-manager-writers` symlink and regular-TOML cases.
3. `pkgs/omarchy/nix-bin/omarchy-theme-set-zed:202-212`: before either redirection to `settings.json`, detect a symlink, leave it and its target intact, and print ownership guidance. Still generate the separate palette; retain the existing JSONC skip and manual theme instruction at lines 198-207 -> verify by `checks.theme-set-zed` regular JSON, JSONC, and managed-link cases.
4. `tests/home-manager-writers.nix` and `flake.nix:2132-2136`: add one cheap check using evaluated `home.activation` data from a small `home-manager.lib.homeManagerConfiguration` fixture with nixd and Zed/Helix enabled. Run the actual activation snippets in a sandbox home with `run` shimmed to execute its argument. Assert a regular JSON merge and TOML append, byte-identical JSONC with actionable stderr, nonfatal skips, and symlink/target inode and contents unchanged. Register the check in `flake.nix`, and `git add` the new file before invoking the flake -> verify by `nix build .#checks.x86_64-linux.home-manager-writers --print-build-logs`.
5. `tests/theme-set-zed.nix:86-113`: extend the existing packaged-setter check with a symlinked `settings.json`; assert the link and target remain unchanged, the skip is reported, and the theme palette is still generated -> verify by `nix build .#checks.x86_64-linux.theme-set-zed --print-build-logs`.

Do not edit `tests/options.nix` while the criticals PR owns it, and do not run `checks.options` locally. The new check exercises the runtime paths without that file. If later review requires an assertion there, rebase after the criticals PR merges and record the plan change in the same commit as that edit. Do not edit protected installer or microVM paths. No workflow changes are needed for a new `checks.<name>`.

## Tests

After `.nix` edits, run `nix fmt`, inspect `git diff --stat`, then run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .`. Use `flock /mnt/data/vmtest/codex-build.lock nix build ...` for each local build, one at a time. Never run VM checks locally.

Prove each new assertion can fail before accepting green, using copies outside the repository under `/mnt/data/vmtest` and restoring with `cp`; never use `git checkout` to restore a break:

1. With the check in place, copy `modules/home.nix` aside, remove only the `mergeJson` symlink guard, build `checks.home-manager-writers`, and capture the symlink failure. Restore with `cp`. Repeat for the `appendToml` guard and capture its failure. Remove the improved JSONC guidance, capture that assertion's failure, then restore and build green.
2. Copy `pkgs/omarchy/nix-bin/omarchy-theme-set-zed` aside, remove only its symlink guard, build `checks.theme-set-zed`, and capture the link/target assertion failure. Restore with `cp` and build green.
3. Before each red build, inspect the diff to prove the intended break landed. Preserve red and green key lines for the PR body; delete temporary logs and copies from the worktree before commit. Confirm `git diff --check` and that only intended files are staged.

## Rollback

Revert the implementation commits on the issue branch and rerun the two cheap checks. A revert restores the previous runtime writers and tests without changing users' existing settings. If a user previously lost a Home Manager link, this change cannot repair that file automatically; they must restore the declaration through their normal NixOS rebuild.
