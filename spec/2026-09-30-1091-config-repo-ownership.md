---
status: approved
issue: 1091
intent: intent/2026-09-30-1091-config-repo-ownership.md
---

# Spec: Create config repo files with the repository user's permissions

## Design

`installer/install.sh:2021-2062` makes the installed user's `/etc/nixos` tree user-owned. `pkgs/omarchy/nix-bin/nixarchy-config-repo:80-93` already avoids sudo for git writes on that tree. Apply the same privilege boundary to the generated files, while checking the directory that each write actually needs:

- In `pkgs/omarchy/nix-bin/nixarchy-config-repo:575`, replace the unconditional `sudo tee` for `.gitignore` with a small write helper. When the destination's parent is writable by the caller, write as the caller. If it is not writable, elevate only when the flake itself is a legacy root-owned directory. Otherwise fail with a permission diagnosis; do not chown an existing file or directory.
- In `pkgs/omarchy/nix-bin/nixarchy-config-repo:725-727,766`, create the CI parent and write either CI file by the same rule. Check the nearest existing parent for a nested `.github/workflows` path: writability of `$FLAKE/.git` does not establish writability of `.github`. If a parent of a user-owned flake is left root-owned by an earlier run, stop with an actionable ownership error instead of silently using sudo again.
- Keep the current generation and prompting flow, managed-install refusal (`:250-293`), and `wgit`/`wcommit` behavior (`:87-103`). No recursive or implicit chown; existing root-owned files stay as they are. The generated GitHub and GitLab workflow contents stay byte-for-byte the same.

## Alternatives rejected

- **Always use sudo, then chown the result:** asks for elevation on every normal install and changes ownership after the fact, including paths the command did not create.
- **Reuse the `.git` writability test for all files:** a user-writable `.git` can coexist with a root-owned `.github` left by the old command. It would choose the wrong privilege for that destination.
- **Remove sudo entirely:** breaks older flakes whose root directory is still root-owned.
- **Rewrite the generated CI templates or change this repository's workflows:** unnecessary for file ownership and outside this issue's CI-gate scope.

## Risks

- A mixed-ownership user flake may have a root-owned CI parent from an earlier run. Its new CI file cannot be written without elevation, so the command must fail clearly rather than report that setup succeeded; the owner can repair the existing ownership explicitly.
- A legacy root-owned flake still needs sudo and can prompt for authentication. A directory permission check must not infer ownership from `.git` or a different parent.
- The command is interactive and can push a remote. Verification must use a sandbox repository and stubs, with no network push or writes to `/etc/nixos`.

## Verification

- Add a cheap `tests/config-repo-ownership.nix` check and expose it through `flake.nix`. Run a copy of the actual `nixarchy-config-repo` script against a sandbox flake: replace only its fixed managed-marker path in the test copy; stub `gum`, `omarchy-done`, and `sudo`; use a local git remote or stop before push. Assert that `.gitignore`, `.github/workflows/check.yml`, and `.gitlab-ci.yml` are created without any sudo call in a user-owned repository and that a pre-existing file is not chowned or overwritten. Cover a root-owned legacy fixture with a sudo stub that records the necessary elevation, and a mixed-ownership fixture that produces the permission diagnosis without implicit chown. Assert generated file contents remain the existing templates.
- Prove the check can fail: copy `pkgs/omarchy/nix-bin/nixarchy-config-repo` aside, restore the unconditional `sudo tee`/`sudo mkdir` write path, and run the check. Capture its explicit failure about sudo on the user-owned fixture. Restore with `cp` (never `git checkout`) and show the check passes. Include the red output in the PR.
- Run `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .` after implementation. Do not run VM checks or `checks.options` locally; `tests/options.nix` is reserved for the criticals PR.
